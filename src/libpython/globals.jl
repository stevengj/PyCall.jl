CPYTHON_OBJECTS = [
	# types
	:PyType_Type,       # builtin 'type'
	:PyBaseObject_Type, # builtin 'object'
	:PySuper_Type,      # builtin 'super'
	:PyLong_Type,       # builtin 'int'
	:PyUnicode_Type,    # builtin 'str'
	:PyTuple_Type,      # builtin 'tuple'
	:PyList_Type,       # builtin 'list'
	:PyBool_Type,       # bulitin 'bool'
	:PyFloat_Type,      # builtin 'float'
	:PyComplex_Type,    # builtin 'complex'
	:PyDict_Type,       # builtin 'dict'
	:PySlice_Type,      # builtin 'slice'
	:PyRange_Type,      # builtin 'range' ('xrange' in python 2)
	# objects
	:_Py_NoneStruct => :Py_None,
	:_Py_TrueStruct => :Py_True,
	:_Py_FalseStruct => :Py_False,
	:_Py_EllipsisObject => :Py_Ellipsis,
	:_Py_NotImplementedStruct => :Py_NotImplemented,
]

CPYTHON_OBJECT_POINTERS = [
	# exception types
	:PyExc_ArithmeticError,
	:PyExc_AttributeError,
	:PyExc_EOFError,
	:PyExc_ImportError,
	:PyExc_IndexError,
	:PyExc_IOError,
	:PyExc_KeyboardInterrupt,
	:PyExc_KeyError,
	:PyExc_MemoryError,
	:PyExc_OverflowError,
	:PyExc_RuntimeError,
	:PyExc_SystemError,
	:PyExc_SyntaxError,
	:PyExc_TypeError,
	:PyExc_ValueError,
	:PyExc_ZeroDivisionError,
]

for name in CPYTHON_OBJECTS
	jname = Symbol(:C, name isa Pair ? name[2] : name)
	jfname = Symbol(jname, :_NewRef)
	@eval const $jname = Ref{PyPtr}(C_NULL)
	@eval function $jfname()
		r = $jname[]
		CPy_IncRef(r)
		r
	end
end

for name in CPYTHON_OBJECT_POINTERS
	jname = Symbol(:C, name isa Pair ? name[2] : name)
	jfname = Symbol(jname, :_NewRef)
	@eval const $jname = Ref{PyPtr}(C_NULL)
	@eval function $jfname()
		r = $jname[]
		CPy_IncRef(r)
		r
	end
end

@eval function capi_init()
	$([begin
	    cname, jname = name isa Pair ? name : name=>name
	    jname = Symbol(:C, jname)
	    cnamesym = QuoteNode(cname)
	    :($jname[] = @pyglobalobj($cnamesym))
	end for name in CPYTHON_OBJECTS]...)
	$([begin
	    cname, jname = name isa Pair ? name : name=>name
	    jname = Symbol(:C, jname)
	    cnamesym = QuoteNode(cname)
	    :($jname[] = @pyglobalobjptr($cnamesym))
	end for name in CPYTHON_OBJECT_POINTERS]...)
end

