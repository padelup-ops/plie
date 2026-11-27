// Runs the bytecode made by CCodeGen_Interp (see Jitter_CodeGen_Interp.h).
//
// The semantics follow the AArch64 back end (shift counts wrap, a division by zero gives a zero
// quotient, float to integer conversions saturate), since that is the code this replaces on iOS.

#include "Jitter_CodeGen_Interp.h"
#include "Jitter.h"

#include <cfenv>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <type_traits>

#if !defined(__GNUC__)
#error "The interpreter needs computed gotos (GCC or Clang)."
#endif

using namespace Jitter;
using namespace Jitter::Interp;

namespace
{
	union V128
	{
		uint8 ub[16];
		int8 sb[16];
		uint16 uh[8];
		int16 sh[8];
		uint32 uw[4];
		int32 sw[4];
		uint64 ud[2];
		float f[4];
	};

	//What a call gives back: two registers on AArch64 and on x86-64 (System V), whatever the callee
	//really returns (nothing, 32, 64 or 128 bits).
	struct RET128
	{
		uint64 lo;
		uint64 hi;
	};
	//Integer and pointer parameters travel in the same registers whatever their width, so one
	//signature serves every function the generated code calls.
	typedef RET128 (*CallTarget)(uint64, uint64, uint64, uint64, uint64, uint64, uint64, uint64);
	typedef void (*JumpTarget)(void*);

	enum
	{
		LOCAL_STACK_SIZE = 2048,
		MAX_PARAMS = 8,
	};

	template <typename T>
	inline T Load(const uint8* p)
	{
		T value;
		memcpy(&value, p, sizeof(T));
		return value;
	}

	template <typename T>
	inline void Store(uint8* p, T value)
	{
		memcpy(p, &value, sizeof(T));
	}

	inline int32 TruncSat(float value)
	{
		if(value != value) return 0;
		if(value >= 2147483648.0f) return std::numeric_limits<int32>::max();
		if(value <= -2147483648.0f) return std::numeric_limits<int32>::min();
		return static_cast<int32>(value);
	}

	inline uint32 ClampFloatBits(uint32 bits)
	{
		//Brings infinities and NaNs back to the largest finite value of the same sign.
		int32 s = static_cast<int32>(bits);
		if(s > 0x7F7FFFFF) s = 0x7F7FFFFF;
		uint32 u = static_cast<uint32>(s);
		if(u > 0xFF7FFFFFU) u = 0xFF7FFFFFU;
		return u;
	}

	template <typename T>
	inline T Sat(int64 value)
	{
		if(value < std::numeric_limits<T>::min()) return std::numeric_limits<T>::min();
		if(value > std::numeric_limits<T>::max()) return std::numeric_limits<T>::max();
		return static_cast<T>(value);
	}

	inline void SetRoundingMode(unsigned int mode)
	{
		int round = FE_TONEAREST;
		switch(mode)
		{
		case CJitter::ROUND_NEAREST:
			round = FE_TONEAREST;
			break;
		case CJitter::ROUND_PLUSINFINITY:
			round = FE_UPWARD;
			break;
		case CJitter::ROUND_MINUSINFINITY:
			round = FE_DOWNWARD;
			break;
		case CJitter::ROUND_TRUNCATE:
			round = FE_TOWARDZERO;
			break;
		}
		if(fegetround() != round) fesetround(round);
	}

	inline bool FpCompare(unsigned int condition, float a, float b)
	{
		switch(condition)
		{
		case CONDITION_EQ:
			return a == b;
		case CONDITION_NE:
			return a != b;
		case CONDITION_BL:
		case CONDITION_LT:
			return a < b;
		case CONDITION_BE:
		case CONDITION_LE:
			return a <= b;
		case CONDITION_AB:
		case CONDITION_GT:
			return a > b;
		case CONDITION_AE:
		case CONDITION_GE:
			return a >= b;
		default:
			return false;
		}
	}
}

void Jitter::Interp::Execute(const void* function, void* context)
{
	// clang-format off
	static const void* const handlers[I_COUNT] =
	{
#define JITTER_INTERP_LABEL(name) &&L_##name,
		JITTER_INTERP_OPS(JITTER_INTERP_LABEL)
#undef JITTER_INTERP_LABEL
	};

	alignas(32) uint8 localStack[LOCAL_STACK_SIZE];
	uint8* heapStack = nullptr;
	uint32 heapStackSize = 0;
	uint8* base[3];
	const INST* ip = nullptr;
	uint64 params[MAX_PARAMS];
	unsigned int paramCount = 0;
	RET128 ret = {0, 0};

	base[SEL_CTX] = static_cast<uint8*>(context);

#define ENTER(blob) \
	do \
	{ \
		auto header = reinterpret_cast<const HEADER*>(blob); \
		if(header->stackSize <= LOCAL_STACK_SIZE) \
		{ \
			base[SEL_STACK] = localStack; \
		} \
		else \
		{ \
			if(header->stackSize > heapStackSize) \
			{ \
				free(heapStack); \
				heapStackSize = header->stackSize; \
				if(posix_memalign(reinterpret_cast<void**>(&heapStack), 32, heapStackSize) != 0) abort(); \
			} \
			base[SEL_STACK] = heapStack; \
		} \
		base[SEL_BLOB] = const_cast<uint8*>(reinterpret_cast<const uint8*>(blob)); \
		ip = reinterpret_cast<const INST*>(base[SEL_BLOB] + sizeof(HEADER)); \
	} while(0)

#define DISPATCH() goto *handlers[ip->op]
#define NEXT() do { ip++; DISPATCH(); } while(0)
#define JUMPTO(offset) do { ip = reinterpret_cast<const INST*>(base[SEL_BLOB] + (offset)); DISPATCH(); } while(0)

#define P(k) (base[ip->sel[k]] + ip->off[k])
#define R(T, k) Load<T>(P(k))
#define W(T, k, value) Store<T>(P(k), (value))
#define IMM64() Load<uint64>(reinterpret_cast<const uint8*>(ip) + IMM64_OFFSET)
#define REFPTR(k) reinterpret_cast<uint8*>(static_cast<uintptr_t>(R(uint64, k)))
#define REFIDX(k, i) (REFPTR(k) + (static_cast<uint64>(R(uint32, i)) * ip->aux))

#define BIN32(name, expr) L_##name: { uint32 a = R(uint32, 1); uint32 b = R(uint32, 2); W(uint32, 0, (expr)); NEXT(); }
#define BIN64(name, expr) L_##name: { uint64 a = R(uint64, 1); uint64 b = R(uint64, 2); W(uint64, 0, (expr)); NEXT(); }
#define SHIFT64(name, expr) L_##name: { uint64 a = R(uint64, 1); uint32 b = R(uint32, 2) & 63; W(uint64, 0, (expr)); NEXT(); }
#define CONDS(M, P) \
	M(P##_EQ, a == b) M(P##_NE, a != b) \
	M(P##_BL, a < b) M(P##_BE, a <= b) M(P##_AB, a > b) M(P##_AE, a >= b) \
	M(P##_LT, SIGNED(a) < SIGNED(b)) M(P##_LE, SIGNED(a) <= SIGNED(b)) M(P##_GT, SIGNED(a) > SIGNED(b)) M(P##_GE, SIGNED(a) >= SIGNED(b))
#define CMP32(name, expr) L_##name: { uint32 a = R(uint32, 1); uint32 b = R(uint32, 2); W(uint32, 0, (expr) ? 1 : 0); NEXT(); }
#define CMP64(name, expr) L_##name: { uint64 a = R(uint64, 1); uint64 b = R(uint64, 2); W(uint32, 0, (expr) ? 1 : 0); NEXT(); }
#define CJ32(name, expr) L_##name: { uint32 a = R(uint32, 1); uint32 b = R(uint32, 2); if(expr) JUMPTO(ip->off[0]); NEXT(); }

#define FP2(name, expr) L_##name: { float a = R(float, 1); W(float, 0, (expr)); NEXT(); }
#define FP3(name, expr) L_##name: { float a = R(float, 1); float b = R(float, 2); W(float, 0, (expr)); NEXT(); }

//Element-wise operations on 128 bits: x and y are the elements of the sources.
#define MD2(name, field, count, expr) L_##name: { V128 a = R(V128, 1); V128 r; for(int i = 0; i < count; i++) { auto x = a.field[i]; r.field[i] = (expr); } W(V128, 0, r); NEXT(); }
#define MD3(name, field, count, expr) L_##name: { V128 a = R(V128, 1); V128 b = R(V128, 2); V128 r; for(int i = 0; i < count; i++) { auto x = a.field[i]; auto y = b.field[i]; r.field[i] = (expr); } W(V128, 0, r); NEXT(); }
//Comparisons give all ones or all zeros in an unsigned element of the same width.
#define MDCMP(name, field, ufield, count, expr) L_##name: { V128 a = R(V128, 1); V128 b = R(V128, 2); V128 r; for(int i = 0; i < count; i++) { auto x = a.field[i]; auto y = b.field[i]; r.ufield[i] = static_cast<std::remove_reference_t<decltype(r.ufield[0])>>((expr) ? ~0ULL : 0ULL); } W(V128, 0, r); NEXT(); }
#define MDSHIFT(name, field, mask, expr) L_##name: { V128 a = R(V128, 1); V128 r; unsigned int n = ip->aux & mask; for(unsigned int i = 0; i < (sizeof(V128) / sizeof(a.field[0])); i++) { auto x = a.field[i]; r.field[i] = static_cast<decltype(x)>(expr); } W(V128, 0, r); NEXT(); }
	// clang-format on

	ENTER(function);
	DISPATCH();

L_END:
	free(heapStack);
	return;

L_BREAK:
	abort();

	//-------------------------------------------------------------------- moves

L_MOV32:
	W(uint32, 0, R(uint32, 1));
	NEXT();
L_MOV64:
	W(uint64, 0, R(uint64, 1));
	NEXT();
L_MOV128:
	W(V128, 0, R(V128, 1));
	NEXT();

	//-------------------------------------------------------------------- 32 bits

#define SIGNED(v) static_cast<int32>(v)
	BIN32(ADD, a + b)
	BIN32(SUB, a - b)
	BIN32(AND, a & b)
	BIN32(OR, a | b)
	BIN32(XOR, a ^ b)
	BIN32(SLL, a << (b & 31))
	BIN32(SRL, a >> (b & 31))
	BIN32(SRA, static_cast<uint32>(SIGNED(a) >> (b & 31)))

L_NOT:
	W(uint32, 0, ~R(uint32, 1));
	NEXT();

L_LZC:
{
	//Leading bits equal to the sign bit, minus one (what the MIPS PLZCW counts).
	uint32 value = R(uint32, 1);
	if(SIGNED(value) < 0) value = ~value;
	W(uint32, 0, (value == 0) ? 31 : static_cast<uint32>(__builtin_clz(value) - 1));
	NEXT();
}

L_MUL:
	W(uint64, 0, static_cast<uint64>(R(uint32, 1)) * static_cast<uint64>(R(uint32, 2)));
	NEXT();
L_MULS:
	W(uint64, 0, static_cast<uint64>(static_cast<int64>(R(int32, 1)) * static_cast<int64>(R(int32, 2))));
	NEXT();

L_DIV:
{
	uint32 a = R(uint32, 1);
	uint32 b = R(uint32, 2);
	uint32 quotient = (b == 0) ? 0 : (a / b);
	uint32 remainder = a - (quotient * b);
	W(uint64, 0, static_cast<uint64>(quotient) | (static_cast<uint64>(remainder) << 32));
	NEXT();
}
L_DIVS:
{
	int32 a = R(int32, 1);
	int32 b = R(int32, 2);
	int32 quotient = 0;
	if(b == 0)
	{
		quotient = 0;
	}
	else if((a == std::numeric_limits<int32>::min()) && (b == -1))
	{
		quotient = a;
	}
	else
	{
		quotient = a / b;
	}
	uint32 remainder = static_cast<uint32>(a) - (static_cast<uint32>(quotient) * static_cast<uint32>(b));
	W(uint64, 0, static_cast<uint64>(static_cast<uint32>(quotient)) | (static_cast<uint64>(remainder) << 32));
	NEXT();
}

	CONDS(CMP32, CMP)

L_SELECT:
	W(uint32, 0, (R(uint32, 1) != 0) ? R(uint32, 2) : R(uint32, 3));
	NEXT();

	//-------------------------------------------------------------------- references

L_RELTOREF:
	W(uint64, 0, static_cast<uint64>(reinterpret_cast<uintptr_t>(context)) + R(uint32, 1));
	NEXT();
L_ADDREF:
	W(uint64, 0, R(uint64, 1) + R(uint32, 2));
	NEXT();
L_ISREFNULL:
	W(uint32, 0, (R(uint64, 1) == 0) ? 1 : 0);
	NEXT();

L_LOAD8:
	W(uint32, 0, Load<uint8>(REFPTR(1)));
	NEXT();
L_LOAD8I:
	W(uint32, 0, Load<uint8>(REFIDX(1, 2)));
	NEXT();
L_LOAD16:
	W(uint32, 0, Load<uint16>(REFPTR(1)));
	NEXT();
L_LOAD16I:
	W(uint32, 0, Load<uint16>(REFIDX(1, 2)));
	NEXT();
L_LOAD32:
	W(uint32, 0, Load<uint32>(REFPTR(1)));
	NEXT();
L_LOAD32I:
	W(uint32, 0, Load<uint32>(REFIDX(1, 2)));
	NEXT();
L_LOAD64:
	W(uint64, 0, Load<uint64>(REFPTR(1)));
	NEXT();
L_LOAD64I:
	W(uint64, 0, Load<uint64>(REFIDX(1, 2)));
	NEXT();
L_LOAD128:
	W(V128, 0, Load<V128>(REFPTR(1)));
	NEXT();
L_LOAD128I:
	W(V128, 0, Load<V128>(REFIDX(1, 2)));
	NEXT();

L_STORE8:
	Store<uint8>(REFPTR(1), static_cast<uint8>(R(uint32, 2)));
	NEXT();
L_STORE8I:
	Store<uint8>(REFIDX(1, 2), static_cast<uint8>(R(uint32, 3)));
	NEXT();
L_STORE16:
	Store<uint16>(REFPTR(1), static_cast<uint16>(R(uint32, 2)));
	NEXT();
L_STORE16I:
	Store<uint16>(REFIDX(1, 2), static_cast<uint16>(R(uint32, 3)));
	NEXT();
L_STORE32:
	Store<uint32>(REFPTR(1), R(uint32, 2));
	NEXT();
L_STORE32I:
	Store<uint32>(REFIDX(1, 2), R(uint32, 3));
	NEXT();
L_STORE64:
	Store<uint64>(REFPTR(1), R(uint64, 2));
	NEXT();
L_STORE64I:
	Store<uint64>(REFIDX(1, 2), R(uint64, 3));
	NEXT();
L_STORE128:
	Store<V128>(REFPTR(1), R(V128, 2));
	NEXT();
L_STORE128I:
	Store<V128>(REFIDX(1, 2), R(V128, 3));
	NEXT();

	//-------------------------------------------------------------------- 64 bits

	BIN64(ADD64, a + b)
	BIN64(SUB64, a - b)
	BIN64(AND64, a & b)
	SHIFT64(SLL64, a << b)
	SHIFT64(SRL64, a >> b)
	SHIFT64(SRA64, static_cast<uint64>(static_cast<int64>(a) >> b))

L_MERGETO64:
	W(uint64, 0, static_cast<uint64>(R(uint32, 1)) | (static_cast<uint64>(R(uint32, 2)) << 32));
	NEXT();
L_EXTLOW64:
	W(uint32, 0, static_cast<uint32>(R(uint64, 1)));
	NEXT();
L_EXTHIGH64:
	W(uint32, 0, static_cast<uint32>(R(uint64, 1) >> 32));
	NEXT();

#undef SIGNED
#define SIGNED(v) static_cast<int64>(v)
	CONDS(CMP64, CMP64)
#undef SIGNED
#define SIGNED(v) static_cast<int32>(v)

	//-------------------------------------------------------------------- 128 and 256 bits

L_MERGETO256:
{
	V128 lo = R(V128, 1);
	V128 hi = R(V128, 2);
	Store<V128>(P(0), lo);
	Store<V128>(P(0) + 16, hi);
	NEXT();
}
L_MD_SRL256:
{
	uint32 offset = (R(uint32, 2) & 0x7F) / 8;
	W(V128, 0, Load<V128>(P(1) + offset));
	NEXT();
}

L_MD_MOV_MASKED:
{
	V128 r = R(V128, 1);
	V128 b = R(V128, 2);
	for(int i = 0; i < 4; i++)
	{
		if(ip->aux & (1 << i)) r.uw[i] = b.uw[i];
	}
	W(V128, 0, r);
	NEXT();
}
L_MD_LOAD_MASKED:
{
	//The reference's address counts in bytes here.
	V128 loaded = Load<V128>(REFPTR(1) + R(uint32, 2));
	V128 r = R(V128, 3);
	for(int i = 0; i < 4; i++)
	{
		if(ip->aux & (1 << i)) r.uw[i] = loaded.uw[i];
	}
	W(V128, 0, r);
	NEXT();
}
L_MD_STORE_MASKED:
{
	uint8* address = REFPTR(1) + R(uint32, 2);
	V128 r = Load<V128>(address);
	V128 value = R(V128, 3);
	for(int i = 0; i < 4; i++)
	{
		if(ip->aux & (1 << i)) r.uw[i] = value.uw[i];
	}
	Store<V128>(address, r);
	NEXT();
}

	MD3(MD_ADD_B, ub, 16, static_cast<uint8>(x + y))
	MD3(MD_ADD_H, uh, 8, static_cast<uint16>(x + y))
	MD3(MD_ADD_W, uw, 4, x + y)
	MD3(MD_ADDSS_B, sb, 16, Sat<int8>(static_cast<int64>(x) + y))
	MD3(MD_ADDSS_H, sh, 8, Sat<int16>(static_cast<int64>(x) + y))
	MD3(MD_ADDSS_W, sw, 4, Sat<int32>(static_cast<int64>(x) + y))
	MD3(MD_ADDUS_B, ub, 16, Sat<uint8>(static_cast<int64>(x) + y))
	MD3(MD_ADDUS_H, uh, 8, Sat<uint16>(static_cast<int64>(x) + y))
	MD3(MD_ADDUS_W, uw, 4, Sat<uint32>(static_cast<int64>(x) + y))

	MD3(MD_SUB_B, ub, 16, static_cast<uint8>(x - y))
	MD3(MD_SUB_H, uh, 8, static_cast<uint16>(x - y))
	MD3(MD_SUB_W, uw, 4, x - y)
	MD3(MD_SUBSS_B, sb, 16, Sat<int8>(static_cast<int64>(x) - y))
	MD3(MD_SUBSS_H, sh, 8, Sat<int16>(static_cast<int64>(x) - y))
	MD3(MD_SUBSS_W, sw, 4, Sat<int32>(static_cast<int64>(x) - y))
	MD3(MD_SUBUS_B, ub, 16, Sat<uint8>(static_cast<int64>(x) - y))
	MD3(MD_SUBUS_H, uh, 8, Sat<uint16>(static_cast<int64>(x) - y))
	MD3(MD_SUBUS_W, uw, 4, Sat<uint32>(static_cast<int64>(x) - y))

	MD2(MD_CLAMP_S, uw, 4, ClampFloatBits(x))

	MDCMP(MD_CMPEQ_B, ub, ub, 16, x == y)
	MDCMP(MD_CMPEQ_H, uh, uh, 8, x == y)
	MDCMP(MD_CMPEQ_W, uw, uw, 4, x == y)
	MDCMP(MD_CMPGT_B, sb, ub, 16, x > y)
	MDCMP(MD_CMPGT_H, sh, uh, 8, x > y)
	MDCMP(MD_CMPGT_W, sw, uw, 4, x > y)

	MD3(MD_MIN_H, sh, 8, (x < y) ? x : y)
	MD3(MD_MIN_W, sw, 4, (x < y) ? x : y)
	MD3(MD_MAX_H, sh, 8, (x > y) ? x : y)
	MD3(MD_MAX_W, sw, 4, (x > y) ? x : y)

	MD3(MD_AND, ud, 2, x & y)
	MD3(MD_OR, ud, 2, x | y)
	MD3(MD_XOR, ud, 2, x ^ y)
	MD2(MD_NOT, ud, 2, ~x)

L_MD_BITSELECT:
{
	//Bits of the first source where the third one is set, bits of the second elsewhere.
	V128 a = R(V128, 1);
	V128 b = R(V128, 2);
	V128 c = R(V128, 3);
	V128 r;
	for(int i = 0; i < 2; i++)
	{
		r.ud[i] = (c.ud[i] & a.ud[i]) | (~c.ud[i] & b.ud[i]);
	}
	W(V128, 0, r);
	NEXT();
}

	MDSHIFT(MD_SLLH, uh, 15, x << n)
	MDSHIFT(MD_SRLH, uh, 15, x >> n)
	MDSHIFT(MD_SRAH, sh, 15, x >> n)
	MDSHIFT(MD_SLLW, uw, 31, x << n)
	MDSHIFT(MD_SRLW, uw, 31, x >> n)
	MDSHIFT(MD_SRAW, sw, 31, x >> n)

L_MD_MAKECLIP:
{
	//For x, y and z: one bit if above the upper bound, the next if below the lower one.
	V128 value = R(V128, 1);
	V128 upper = R(V128, 2);
	V128 lower = R(V128, 3);
	uint32 result = 0;
	for(int i = 0; i < 3; i++)
	{
		if(value.f[i] > upper.f[i]) result |= (1 << (i * 2));
		if(value.f[i] < lower.f[i]) result |= (1 << ((i * 2) + 1));
	}
	W(uint32, 0, result);
	NEXT();
}
L_MD_MAKESZ:
{
	//Sign flags in the high nibble and zero flags in the low one, the first element in the top bit of each.
	V128 value = R(V128, 1);
	uint32 result = 0;
	for(int i = 0; i < 4; i++)
	{
		if(value.sw[i] < 0) result |= (0x80 >> i);
		if(value.f[i] == 0) result |= (0x08 >> i);
	}
	W(uint32, 0, result);
	NEXT();
}

L_MD_TOINT32_TRUNC_S:
{
	V128 a = R(V128, 1);
	V128 r;
	for(int i = 0; i < 4; i++)
	{
		r.sw[i] = TruncSat(a.f[i]);
	}
	W(V128, 0, r);
	NEXT();
}

L_MD_TOSINGLE_I32:
{
	V128 a = R(V128, 1);
	V128 r;
	for(int i = 0; i < 4; i++)
	{
		r.f[i] = static_cast<float>(a.sw[i]);
	}
	W(V128, 0, r);
	NEXT();
}

L_MD_EXPAND_W:
{
	uint32 value = R(uint32, 1);
	V128 r;
	for(int i = 0; i < 4; i++)
	{
		r.uw[i] = value;
	}
	W(V128, 0, r);
	NEXT();
}
L_MD_EXPAND_WL:
{
	V128 a = R(V128, 1);
	V128 r;
	for(int i = 0; i < 4; i++)
	{
		r.uw[i] = a.uw[ip->aux & 3];
	}
	W(V128, 0, r);
	NEXT();
}

	//Interleaving: the second source gives the even elements, the first the odd ones.
#define MDUNPACK(name, field, count, start) L_##name: { V128 a = R(V128, 1); V128 b = R(V128, 2); V128 r; for(int i = 0; i < (count / 2); i++) { r.field[i * 2] = b.field[start + i]; r.field[(i * 2) + 1] = a.field[start + i]; } W(V128, 0, r); NEXT(); }
	MDUNPACK(MD_UNPACK_LOWER_BH, ub, 16, 0)
	MDUNPACK(MD_UNPACK_LOWER_HW, uh, 8, 0)
	MDUNPACK(MD_UNPACK_LOWER_WD, uw, 4, 0)
	MDUNPACK(MD_UNPACK_UPPER_BH, ub, 16, 8)
	MDUNPACK(MD_UNPACK_UPPER_HW, uh, 8, 4)
	MDUNPACK(MD_UNPACK_UPPER_WD, uw, 4, 2)

L_MD_PACK_HB:
{
	//Narrowing keeps the low half of each element: the second source first, then the first.
	V128 a = R(V128, 1);
	V128 b = R(V128, 2);
	V128 r;
	for(int i = 0; i < 8; i++)
	{
		r.ub[i] = static_cast<uint8>(b.uh[i]);
		r.ub[i + 8] = static_cast<uint8>(a.uh[i]);
	}
	W(V128, 0, r);
	NEXT();
}
L_MD_PACK_WH:
{
	V128 a = R(V128, 1);
	V128 b = R(V128, 2);
	V128 r;
	for(int i = 0; i < 4; i++)
	{
		r.uh[i] = static_cast<uint16>(b.uw[i]);
		r.uh[i + 4] = static_cast<uint16>(a.uw[i]);
	}
	W(V128, 0, r);
	NEXT();
}

	MD3(MD_ADD_S, f, 4, x + y)
	MD3(MD_SUB_S, f, 4, x - y)
	MD3(MD_MUL_S, f, 4, x * y)
	MD3(MD_DIV_S, f, 4, x / y)
	MD2(MD_ABS_S, uw, 4, x & 0x7FFFFFFFU)
	MD2(MD_NEG_S, uw, 4, x ^ 0x80000000U)
	MD3(MD_MIN_S, f, 4, (x < y) ? x : y)
	MD3(MD_MAX_S, f, 4, (x > y) ? x : y)
	MDCMP(MD_CMPLT_S, f, uw, 4, x < y)
	MDCMP(MD_CMPGT_S, f, uw, 4, x > y)

	//-------------------------------------------------------------------- single floats

	FP3(FP_ADD_S, a + b)
	FP3(FP_SUB_S, a - b)
	FP3(FP_MUL_S, a * b)
	FP3(FP_DIV_S, a / b)
	FP3(FP_MIN_S, (a < b) ? a : b)
	FP3(FP_MAX_S, (a > b) ? a : b)
	FP2(FP_SQRT_S, sqrtf(a))
	FP2(FP_RSQRT_S, 1.0f / sqrtf(a))
	FP2(FP_RCPL_S, 1.0f / a)

L_FP_ABS_S:
	W(uint32, 0, R(uint32, 1) & 0x7FFFFFFFU);
	NEXT();
L_FP_NEG_S:
	W(uint32, 0, R(uint32, 1) ^ 0x80000000U);
	NEXT();
L_FP_CLAMP_S:
	W(uint32, 0, ClampFloatBits(R(uint32, 1)));
	NEXT();
L_FP_CMP_S:
	W(uint32, 0, FpCompare(ip->aux, R(float, 1), R(float, 2)) ? 1 : 0);
	NEXT();
L_FP_TOINT32_TRUNC_S:
	W(int32, 0, TruncSat(R(float, 1)));
	NEXT();
L_FP_TOSINGLE_I32:
	W(float, 0, static_cast<float>(R(int32, 1)));
	NEXT();
L_FP_SETROUNDINGMODE:
	SetRoundingMode(ip->aux);
	NEXT();

	//-------------------------------------------------------------------- calls

L_PARAM32:
	params[paramCount++ & (MAX_PARAMS - 1)] = R(uint32, 1);
	NEXT();
L_PARAM64:
	params[paramCount++ & (MAX_PARAMS - 1)] = R(uint64, 1);
	NEXT();
L_PARAMCTX:
	params[paramCount++ & (MAX_PARAMS - 1)] = static_cast<uint64>(reinterpret_cast<uintptr_t>(context));
	NEXT();
L_PARAMADDR:
	params[paramCount++ & (MAX_PARAMS - 1)] = static_cast<uint64>(reinterpret_cast<uintptr_t>(P(1)));
	NEXT();

L_CALL:
{
	//The last parameter pushed is the first argument.
	uint64 args[MAX_PARAMS] = {};
	unsigned int count = ip->aux;
	for(unsigned int i = 0; (i < count) && (paramCount != 0); i++)
	{
		args[i] = params[--paramCount];
	}
	auto target = reinterpret_cast<CallTarget>(static_cast<uintptr_t>(IMM64()));
	ret = target(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
	NEXT();
}

L_RETVAL32:
	W(uint32, 0, static_cast<uint32>(ret.lo));
	NEXT();
L_RETVAL64:
	W(uint64, 0, ret.lo);
	NEXT();
L_RETVAL128:
	Store<uint64>(P(0), ret.lo);
	Store<uint64>(P(0) + 8, ret.hi);
	NEXT();

	//-------------------------------------------------------------------- jumps

L_JMP:
	JUMPTO(ip->off[0]);

	CONDS(CJ32, CJ)

L_CJREF_EQ:
	if(R(uint64, 1) == 0) JUMPTO(ip->off[0]);
	NEXT();
L_CJREF_NE:
	if(R(uint64, 1) != 0) JUMPTO(ip->off[0]);
	NEXT();

L_EXTJMP:
{
	//Control goes to another function for good: another piece of bytecode carries on here, in the same
	//frame; anything else is native code, called before leaving.
	auto target = static_cast<uintptr_t>(IMM64());
	if(Load<uint64>(reinterpret_cast<const uint8*>(target)) == MAGIC)
	{
		paramCount = 0;
		ENTER(reinterpret_cast<const void*>(target));
		DISPATCH();
	}
	free(heapStack);
	reinterpret_cast<JumpTarget>(target)(context);
	return;
}
}
