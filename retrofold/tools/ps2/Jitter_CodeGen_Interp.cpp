#include "Jitter_CodeGen_Interp.h"

#include <stdexcept>

using namespace Jitter;
using namespace Jitter::Interp;

namespace
{
	enum KIND
	{
		K32,
		K64,
		K128,
		K256,
		KREF,
		KCTX,
		KPTR,
	};

	KIND Kind(const CSymbol* symbol)
	{
		switch(symbol->m_type)
		{
		case SYM_CONTEXT:
			return KCTX;
		case SYM_CONSTANTPTR:
			return KPTR;
		case SYM_CONSTANT:
		case SYM_RELATIVE:
		case SYM_TEMPORARY:
		case SYM_FP_RELATIVE32:
		case SYM_FP_TEMPORARY32:
			return K32;
		case SYM_REL_REFERENCE:
		case SYM_TMP_REFERENCE:
			return KREF;
		case SYM_RELATIVE64:
		case SYM_TEMPORARY64:
		case SYM_CONSTANT64:
			return K64;
		case SYM_RELATIVE128:
		case SYM_TEMPORARY128:
			return K128;
		case SYM_TEMPORARY256:
			return K256;
		default:
			//Registers: this back end asks for none.
			throw std::runtime_error("Interp: unexpected symbol type.");
		}
	}

	void SetImm64(INST& inst, uint64 value)
	{
		inst.off[2] = static_cast<uint32>(value);
		inst.off[3] = static_cast<uint32>(value >> 32);
	}
}

void CCodeGen_Interp::SetStream(Framework::CStream* stream)
{
	m_stream = stream;
}

void CCodeGen_Interp::RegisterExternalSymbols(CObjectFile*) const
{
}

unsigned int CCodeGen_Interp::GetAvailableRegisterCount() const
{
	return 0;
}

unsigned int CCodeGen_Interp::GetAvailableMdRegisterCount() const
{
	return 0;
}

bool CCodeGen_Interp::Has128BitsCallOperands() const
{
	//Passed by address, as the native 64-bit back ends do.
	return true;
}

bool CCodeGen_Interp::CanHold128BitsReturnValueInRegisters() const
{
	//A 16-byte value comes back in two registers on both AArch64 and x86-64 (System V).
	return true;
}

bool CCodeGen_Interp::SupportsExternalJumps() const
{
	return true;
}

bool CCodeGen_Interp::SupportsCmpSelect() const
{
	return false;
}

uint32 CCodeGen_Interp::GetPointerSize() const
{
	return 8;
}

INST& CCodeGen_Interp::Add(OP op)
{
	INST inst = {};
	inst.op = op;
	m_insts.push_back(inst);
	return m_insts.back();
}

uint32 CCodeGen_Interp::Literal(uint64 value)
{
	auto it = m_literalIndex.find(value);
	if(it != m_literalIndex.end()) return it->second;
	uint32 index = static_cast<uint32>(m_literals.size());
	m_literals.push_back(value);
	m_literalIndex.emplace(value, index);
	return index;
}

void CCodeGen_Interp::Operand(INST& inst, unsigned int slot, CSymbol* symbol)
{
	switch(symbol->m_type)
	{
	case SYM_RELATIVE:
	case SYM_RELATIVE64:
	case SYM_RELATIVE128:
	case SYM_FP_RELATIVE32:
	case SYM_REL_REFERENCE:
		inst.sel[slot] = SEL_CTX;
		inst.off[slot] = symbol->m_valueLow;
		break;
	case SYM_TEMPORARY:
	case SYM_TEMPORARY64:
	case SYM_TEMPORARY128:
	case SYM_TEMPORARY256:
	case SYM_FP_TEMPORARY32:
	case SYM_TMP_REFERENCE:
		inst.sel[slot] = SEL_STACK;
		inst.off[slot] = symbol->m_stackLocation;
		break;
	case SYM_CONSTANT:
		//The pool offset is finished once the number of instructions is known.
		inst.sel[slot] = SEL_BLOB;
		inst.off[slot] = Literal(symbol->m_valueLow) * 8;
		break;
	case SYM_CONSTANT64:
		inst.sel[slot] = SEL_BLOB;
		inst.off[slot] = Literal(symbol->GetConstant64()) * 8;
		break;
	default:
		throw std::runtime_error("Interp: operand can't be addressed.");
	}
}

void CCodeGen_Interp::Emit(const STATEMENT& statement)
{
	auto dst = statement.dst ? statement.dst->GetSymbol().get() : nullptr;
	auto src1 = statement.src1 ? statement.src1->GetSymbol().get() : nullptr;
	auto src2 = statement.src2 ? statement.src2->GetSymbol().get() : nullptr;
	auto src3 = statement.src3 ? statement.src3->GetSymbol().get() : nullptr;

	//The usual shape: every operand present goes in its slot.
	const auto generic =
	    [&](OP op) -> INST& {
		    auto& inst = Add(op);
		    if(dst) Operand(inst, 0, dst);
		    if(src1) Operand(inst, 1, src1);
		    if(src2) Operand(inst, 2, src2);
		    if(src3) Operand(inst, 3, src3);
		    return inst;
	    };
	const auto condOp =
	    [&](OP first) {
		    if(statement.jmpCondition < CONDITION_EQ || statement.jmpCondition > CONDITION_GE)
		    {
			    throw std::runtime_error("Interp: bad condition.");
		    }
		    return static_cast<OP>(first + (statement.jmpCondition - CONDITION_EQ));
	    };
	const auto scale =
	    [&]() {
		    return static_cast<uint16>(static_cast<uint8>(statement.jmpCondition));
	    };

	switch(statement.op)
	{
	case OP_NOP:
		break;
	case OP_LABEL:
		m_labels[statement.jmpBlock] = m_insts.size();
		break;
	case OP_BREAK:
		Add(I_BREAK);
		break;

	case OP_MOV:
	case OP_FP_LDCST:
		switch(Kind(dst))
		{
		case K32:
			generic(I_MOV32);
			break;
		case K64:
		case KREF:
			generic(I_MOV64);
			break;
		case K128:
			generic(I_MOV128);
			break;
		default:
			throw std::runtime_error("Interp: bad move.");
		}
		break;

		// clang-format off
#define SAME(name) case OP_##name: generic(I_##name); break;
	SAME(ADD) SAME(SUB) SAME(AND) SAME(OR) SAME(XOR) SAME(NOT) SAME(LZC) SAME(SRA) SAME(SRL) SAME(SLL)
	SAME(MUL) SAME(MULS) SAME(DIV) SAME(DIVS)
	SAME(SELECT)
	SAME(RELTOREF) SAME(ADDREF) SAME(ISREFNULL)
	SAME(ADD64) SAME(SUB64) SAME(AND64) SAME(MERGETO64) SAME(EXTLOW64) SAME(EXTHIGH64) SAME(SRA64) SAME(SRL64) SAME(SLL64)
	SAME(MERGETO256) SAME(MD_SRL256)
	SAME(MD_ADD_B) SAME(MD_ADD_H) SAME(MD_ADD_W) SAME(MD_ADDSS_B) SAME(MD_ADDSS_H) SAME(MD_ADDSS_W)
	SAME(MD_ADDUS_B) SAME(MD_ADDUS_H) SAME(MD_ADDUS_W)
	SAME(MD_SUB_B) SAME(MD_SUB_H) SAME(MD_SUB_W) SAME(MD_SUBSS_B) SAME(MD_SUBSS_H) SAME(MD_SUBSS_W)
	SAME(MD_SUBUS_B) SAME(MD_SUBUS_H) SAME(MD_SUBUS_W)
	SAME(MD_CLAMP_S)
	SAME(MD_CMPEQ_B) SAME(MD_CMPEQ_H) SAME(MD_CMPEQ_W) SAME(MD_CMPGT_B) SAME(MD_CMPGT_H) SAME(MD_CMPGT_W)
	SAME(MD_MIN_H) SAME(MD_MIN_W) SAME(MD_MAX_H) SAME(MD_MAX_W)
	SAME(MD_AND) SAME(MD_BITSELECT) SAME(MD_OR) SAME(MD_XOR) SAME(MD_NOT)
	SAME(MD_MAKECLIP) SAME(MD_MAKESZ) SAME(MD_TOINT32_TRUNC_S) SAME(MD_TOSINGLE_I32)
	SAME(MD_UNPACK_LOWER_BH) SAME(MD_UNPACK_LOWER_HW) SAME(MD_UNPACK_LOWER_WD)
	SAME(MD_UNPACK_UPPER_BH) SAME(MD_UNPACK_UPPER_HW) SAME(MD_UNPACK_UPPER_WD)
	SAME(MD_PACK_HB) SAME(MD_PACK_WH)
	SAME(MD_ADD_S) SAME(MD_SUB_S) SAME(MD_MUL_S) SAME(MD_DIV_S) SAME(MD_ABS_S) SAME(MD_NEG_S)
	SAME(MD_MIN_S) SAME(MD_MAX_S) SAME(MD_CMPLT_S) SAME(MD_CMPGT_S)
	SAME(FP_ADD_S) SAME(FP_SUB_S) SAME(FP_MUL_S) SAME(FP_DIV_S) SAME(FP_SQRT_S) SAME(FP_RSQRT_S) SAME(FP_RCPL_S)
	SAME(FP_ABS_S) SAME(FP_NEG_S) SAME(FP_MAX_S) SAME(FP_MIN_S) SAME(FP_CLAMP_S)
	SAME(FP_TOINT32_TRUNC_S) SAME(FP_TOSINGLE_I32)
#undef SAME
		// clang-format on

	case OP_CMP:
		generic(condOp(I_CMP_EQ));
		break;
	case OP_CMP64:
		generic(condOp(I_CMP64_EQ));
		break;
	case OP_FP_CMP_S:
		generic(I_FP_CMP_S).aux = static_cast<uint16>(statement.jmpCondition);
		break;
	case OP_FP_SETROUNDINGMODE:
		Add(I_FP_SETROUNDINGMODE).aux = static_cast<uint16>(src1->m_valueLow);
		break;

	case OP_MD_SRLH:
	case OP_MD_SRAH:
	case OP_MD_SLLH:
	case OP_MD_SRLW:
	case OP_MD_SRAW:
	case OP_MD_SLLW:
	{
		static const std::map<OPERATION, OP> ops =
		    {
		        {OP_MD_SRLH, I_MD_SRLH},
		        {OP_MD_SRAH, I_MD_SRAH},
		        {OP_MD_SLLH, I_MD_SLLH},
		        {OP_MD_SRLW, I_MD_SRLW},
		        {OP_MD_SRAW, I_MD_SRAW},
		        {OP_MD_SLLW, I_MD_SLLW},
		    };
		if(src2->m_type != SYM_CONSTANT) throw std::runtime_error("Interp: shift amount must be constant.");
		auto& inst = Add(ops.at(statement.op));
		Operand(inst, 0, dst);
		Operand(inst, 1, src1);
		inst.aux = static_cast<uint16>(src2->m_valueLow);
	}
	break;

	case OP_MD_EXPAND_W:
		if(Kind(src1) == K128)
		{
			auto& inst = Add(I_MD_EXPAND_WL);
			Operand(inst, 0, dst);
			Operand(inst, 1, src1);
			inst.aux = static_cast<uint16>(src2->m_valueLow & 3);
		}
		else
		{
			generic(I_MD_EXPAND_W);
		}
		break;

	case OP_MD_MOV_MASKED:
		generic(I_MD_MOV_MASKED).aux = scale();
		break;
	case OP_MD_LOADFROMREF_MASKED:
		generic(I_MD_LOAD_MASKED).aux = scale();
		break;
	case OP_MD_STOREATREF_MASKED:
		generic(I_MD_STORE_MASKED).aux = scale();
		break;

	case OP_LOADFROMREF:
	case OP_LOAD8FROMREF:
	case OP_LOAD16FROMREF:
	{
		OP op = I_LOAD32;
		if(statement.op == OP_LOAD8FROMREF)
		{
			op = I_LOAD8;
		}
		else if(statement.op == OP_LOAD16FROMREF)
		{
			op = I_LOAD16;
		}
		else
		{
			switch(Kind(dst))
			{
			case K32:
				op = I_LOAD32;
				break;
			case K64:
			case KREF:
				op = I_LOAD64;
				break;
			case K128:
				op = I_LOAD128;
				break;
			default:
				throw std::runtime_error("Interp: bad load.");
			}
		}
		//The indexed form follows the plain one in the list.
		if(src2) op = static_cast<OP>(op + 1);
		auto& inst = generic(op);
		if(src2) inst.aux = scale();
	}
	break;

	case OP_STOREATREF:
	case OP_STORE8ATREF:
	case OP_STORE16ATREF:
	{
		auto value = src3 ? src3 : src2;
		OP op = I_STORE32;
		if(statement.op == OP_STORE8ATREF)
		{
			op = I_STORE8;
		}
		else if(statement.op == OP_STORE16ATREF)
		{
			op = I_STORE16;
		}
		else
		{
			switch(Kind(value))
			{
			case K32:
				op = I_STORE32;
				break;
			case K64:
			case KREF:
				op = I_STORE64;
				break;
			case K128:
				op = I_STORE128;
				break;
			default:
				throw std::runtime_error("Interp: bad store.");
			}
		}
		if(src3) op = static_cast<OP>(op + 1);
		auto& inst = generic(op);
		if(src3) inst.aux = scale();
	}
	break;

	case OP_PARAM:
	case OP_PARAM_RET:
		switch(Kind(src1))
		{
		case KCTX:
			Add(I_PARAMCTX);
			break;
		case K32:
			generic(I_PARAM32);
			break;
		case K64:
		case KREF:
			generic(I_PARAM64);
			break;
		case K128:
			generic(I_PARAMADDR);
			break;
		default:
			throw std::runtime_error("Interp: bad parameter.");
		}
		break;

	case OP_CALL:
	{
		auto& inst = Add(I_CALL);
		SetImm64(inst, src1->GetConstantPtr());
		inst.aux = static_cast<uint16>(src2->m_valueLow);
		if(inst.aux > 8) throw std::runtime_error("Interp: too many parameters.");
	}
	break;

	case OP_RETVAL:
		switch(Kind(dst))
		{
		case K32:
			generic(I_RETVAL32);
			break;
		case K64:
		case KREF:
			generic(I_RETVAL64);
			break;
		case K128:
			generic(I_RETVAL128);
			break;
		default:
			throw std::runtime_error("Interp: bad return value.");
		}
		break;

	case OP_EXTERNJMP:
	case OP_EXTERNJMP_DYN:
	{
		auto& inst = Add(I_EXTJMP);
		SetImm64(inst, src1->GetConstantPtr());
		if(statement.op == OP_EXTERNJMP_DYN)
		{
			m_dynamicJumps.emplace_back(m_insts.size() - 1, src1->GetConstantPtr());
		}
	}
	break;

	case OP_JMP:
	case OP_GOTO:
		Add(I_JMP);
		m_fixups.push_back({m_insts.size() - 1, statement.jmpBlock});
		break;

	case OP_CONDJMP:
	{
		OP op = I_CJ_EQ;
		if(Kind(src1) == KREF)
		{
			//A reference is only ever compared with null.
			if((src2->m_type != SYM_CONSTANT) || (src2->m_valueLow != 0)) throw std::runtime_error("Interp: bad reference test.");
			switch(statement.jmpCondition)
			{
			case CONDITION_EQ:
				op = I_CJREF_EQ;
				break;
			case CONDITION_NE:
				op = I_CJREF_NE;
				break;
			default:
				throw std::runtime_error("Interp: bad reference test.");
			}
		}
		else
		{
			op = condOp(I_CJ_EQ);
		}
		auto& inst = Add(op);
		Operand(inst, 1, src1);
		Operand(inst, 2, src2);
		m_fixups.push_back({m_insts.size() - 1, statement.jmpBlock});
	}
	break;

	default:
		throw std::runtime_error("Interp: operation not handled.");
	}
}

void CCodeGen_Interp::GenerateCode(const StatementList& statements, unsigned int stackSize)
{
	m_insts.clear();
	m_literals.clear();
	m_literalIndex.clear();
	m_labels.clear();
	m_fixups.clear();
	m_dynamicJumps.clear();

	for(const auto& statement : statements)
	{
		Emit(statement);
	}
	Add(I_END);

	const auto instOffset =
	    [](size_t index) {
		    return static_cast<uint32>(sizeof(HEADER) + (index * sizeof(INST)));
	    };

	//A label nothing marks is the end of the function.
	for(const auto& fixup : m_fixups)
	{
		auto label = m_labels.find(fixup.label);
		size_t target = (label != m_labels.end()) ? label->second : (m_insts.size() - 1);
		m_insts[fixup.instIndex].off[0] = instOffset(target);
	}

	uint32 poolBase = instOffset(m_insts.size());
	for(auto& inst : m_insts)
	{
		for(unsigned int slot = 0; slot < 4; slot++)
		{
			if(inst.sel[slot] == SEL_BLOB) inst.off[slot] += poolBase;
		}
	}

	HEADER header = {};
	header.magic = MAGIC;
	header.stackSize = (stackSize + 0x1F) & ~0x1F;
	header.instCount = static_cast<uint32>(m_insts.size());

	auto base = static_cast<uint32>(m_stream->Tell());
	m_stream->Write(&header, sizeof(header));
	m_stream->Write(m_insts.data(), m_insts.size() * sizeof(INST));
	if(!m_literals.empty())
	{
		m_stream->Write(m_literals.data(), m_literals.size() * sizeof(uint64));
	}

	if(m_externalSymbolReferencedHandler)
	{
		for(const auto& jump : m_dynamicJumps)
		{
			m_externalSymbolReferencedHandler(jump.second, base + instOffset(jump.first) + IMM64_OFFSET, SYMBOL_REF_TYPE::NATIVE_POINTER);
		}
	}
}
