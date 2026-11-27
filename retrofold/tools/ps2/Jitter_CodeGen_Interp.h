#pragma once

// An interpreting back end for the code generator, for platforms where an app may not create
// executable memory (an iOS app from TestFlight or the App Store). Instead of machine code, the
// "code" of a function is a small bytecode: a header, fixed-size instructions and a pool of
// constants. CMemoryFunction runs it with Jitter::Interp::Execute.
//
// Every operand is a memory location: an offset in the context, in the function's stack frame or
// in the function's own constant pool. So one handler per operation is enough, whatever the mix of
// relatives, temporaries and constants.

#include <map>
#include <vector>
#include "Jitter_CodeGen.h"

namespace Jitter
{
	namespace Interp
	{
		//The first 8 bytes of every function, so that a jump target can be told from native code.
		static const uint64 MAGIC = 0x9E3779B97F4A7C15ULL ^ 0x494E54455250ULL;

		enum SEL : uint8
		{
			SEL_CTX = 0,
			SEL_STACK = 1,
			SEL_BLOB = 2,
		};

		struct HEADER
		{
			uint64 magic;
			uint32 stackSize;
			uint32 instCount;
		};
		static_assert(sizeof(HEADER) == 16, "HEADER size");

		struct INST
		{
			uint16 op;
			uint8 sel[4];
			uint16 aux;
			uint32 off[4];
		};
		static_assert(sizeof(INST) == 24, "INST size");

		//A 64-bit immediate (a function or jump target) lives in off[2] and off[3].
		static const uint32 IMM64_OFFSET = 16;

		// clang-format off
#define JITTER_INTERP_CONDS(X, P) \
	X(P##_EQ) X(P##_NE) X(P##_BL) X(P##_BE) X(P##_AB) X(P##_AE) X(P##_LT) X(P##_LE) X(P##_GT) X(P##_GE)

#define JITTER_INTERP_OPS(X) \
	X(END) X(BREAK) \
	X(MOV32) X(MOV64) X(MOV128) \
	X(ADD) X(SUB) X(AND) X(OR) X(XOR) X(NOT) X(LZC) X(SRA) X(SRL) X(SLL) \
	X(MUL) X(MULS) X(DIV) X(DIVS) \
	JITTER_INTERP_CONDS(X, CMP) \
	X(SELECT) \
	X(RELTOREF) X(ADDREF) X(ISREFNULL) \
	X(LOAD8) X(LOAD8I) X(LOAD16) X(LOAD16I) X(LOAD32) X(LOAD32I) X(LOAD64) X(LOAD64I) X(LOAD128) X(LOAD128I) \
	X(STORE8) X(STORE8I) X(STORE16) X(STORE16I) X(STORE32) X(STORE32I) X(STORE64) X(STORE64I) X(STORE128) X(STORE128I) \
	X(ADD64) X(SUB64) X(AND64) X(MERGETO64) X(EXTLOW64) X(EXTHIGH64) X(SRA64) X(SRL64) X(SLL64) \
	JITTER_INTERP_CONDS(X, CMP64) \
	X(MERGETO256) X(MD_SRL256) \
	X(MD_MOV_MASKED) X(MD_LOAD_MASKED) X(MD_STORE_MASKED) \
	X(MD_ADD_B) X(MD_ADD_H) X(MD_ADD_W) X(MD_ADDSS_B) X(MD_ADDSS_H) X(MD_ADDSS_W) X(MD_ADDUS_B) X(MD_ADDUS_H) X(MD_ADDUS_W) \
	X(MD_SUB_B) X(MD_SUB_H) X(MD_SUB_W) X(MD_SUBSS_B) X(MD_SUBSS_H) X(MD_SUBSS_W) X(MD_SUBUS_B) X(MD_SUBUS_H) X(MD_SUBUS_W) \
	X(MD_CLAMP_S) \
	X(MD_CMPEQ_B) X(MD_CMPEQ_H) X(MD_CMPEQ_W) X(MD_CMPGT_B) X(MD_CMPGT_H) X(MD_CMPGT_W) \
	X(MD_MIN_H) X(MD_MIN_W) X(MD_MAX_H) X(MD_MAX_W) \
	X(MD_AND) X(MD_BITSELECT) X(MD_OR) X(MD_XOR) X(MD_NOT) \
	X(MD_SRLH) X(MD_SRAH) X(MD_SLLH) X(MD_SRLW) X(MD_SRAW) X(MD_SLLW) \
	X(MD_MAKECLIP) X(MD_MAKESZ) X(MD_TOINT32_TRUNC_S) X(MD_TOSINGLE_I32) \
	X(MD_EXPAND_W) X(MD_EXPAND_WL) \
	X(MD_UNPACK_LOWER_BH) X(MD_UNPACK_LOWER_HW) X(MD_UNPACK_LOWER_WD) \
	X(MD_UNPACK_UPPER_BH) X(MD_UNPACK_UPPER_HW) X(MD_UNPACK_UPPER_WD) \
	X(MD_PACK_HB) X(MD_PACK_WH) \
	X(MD_ADD_S) X(MD_SUB_S) X(MD_MUL_S) X(MD_DIV_S) X(MD_ABS_S) X(MD_NEG_S) X(MD_MIN_S) X(MD_MAX_S) X(MD_CMPLT_S) X(MD_CMPGT_S) \
	X(FP_ADD_S) X(FP_SUB_S) X(FP_MUL_S) X(FP_DIV_S) X(FP_SQRT_S) X(FP_RSQRT_S) X(FP_RCPL_S) X(FP_ABS_S) X(FP_NEG_S) \
	X(FP_MAX_S) X(FP_MIN_S) X(FP_CMP_S) X(FP_CLAMP_S) X(FP_TOINT32_TRUNC_S) X(FP_TOSINGLE_I32) X(FP_SETROUNDINGMODE) \
	X(PARAM32) X(PARAM64) X(PARAMCTX) X(PARAMADDR) X(CALL) X(RETVAL32) X(RETVAL64) X(RETVAL128) \
	X(JMP) \
	JITTER_INTERP_CONDS(X, CJ) \
	X(CJREF_EQ) X(CJREF_NE) \
	X(EXTJMP)
		// clang-format on

		enum OP : uint16
		{
#define JITTER_INTERP_ENUM(name) I_##name,
			JITTER_INTERP_OPS(JITTER_INTERP_ENUM)
#undef JITTER_INTERP_ENUM
			    I_COUNT
		};

		//Runs a function made by CCodeGen_Interp with the given context.
		void Execute(const void* function, void* context);
	}

	class CCodeGen_Interp : public CCodeGen
	{
	public:
		void SetStream(Framework::CStream*) override;
		void GenerateCode(const StatementList&, unsigned int) override;
		void RegisterExternalSymbols(CObjectFile*) const override;

		unsigned int GetAvailableRegisterCount() const override;
		unsigned int GetAvailableMdRegisterCount() const override;
		bool Has128BitsCallOperands() const override;
		bool CanHold128BitsReturnValueInRegisters() const override;
		bool SupportsExternalJumps() const override;
		bool SupportsCmpSelect() const override;
		uint32 GetPointerSize() const override;

	private:
		struct FIXUP
		{
			size_t instIndex;
			uint32 label;
		};

		Interp::INST& Add(Interp::OP);
		void Operand(Interp::INST&, unsigned int, CSymbol*);
		uint32 Literal(uint64);
		void Emit(const STATEMENT&);

		Framework::CStream* m_stream = nullptr;
		std::vector<Interp::INST> m_insts;
		std::vector<uint64> m_literals;
		std::map<uint64, uint32> m_literalIndex;
		std::map<uint32, size_t> m_labels;
		std::vector<FIXUP> m_fixups;
		std::vector<std::pair<size_t, uintptr_t>> m_dynamicJumps;
	};
}
