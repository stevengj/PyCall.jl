CPYTHON_FUNCTIONS = [
	# initialization
	(:Py_IsInitialized, Cint, ()),
	(:Py_Initialize, Cvoid, ()),
	(:Py_InitializeEx, Cvoid, (Cint,)),
	(:Py_SetPythonHome, Cvoid, (Cwstring,)),
	(:Py_SetProgramName, Cvoid, (Cwstring,)),
	(:Py_GetVersion, Cstring, ()),
	(:Py_AtExit, Cint, (Ptr{Cvoid},)),
	(:Py_Finalize, Cvoid, ()),
	# refcount
	(:Py_DecRef, Cvoid, (PyPtr,)),
	(:Py_IncRef, Cvoid, (PyPtr,)),
	# errors
	(:PyErr_Clear, Cvoid, ()),
	(:PyErr_Print, Cvoid, ()),
	(:PyErr_Occurred, PyPtr, ()),
	(:PyErr_Fetch, Cvoid, (Ptr{PyPtr}, Ptr{PyPtr}, Ptr{PyPtr})),
	(:PyErr_NormalizeException, Cvoid, (Ptr{PyPtr}, Ptr{PyPtr}, Ptr{PyPtr})),
	# import
	(:PyImport_ImportModule, PyPtr, (Cstring,)),
	(:PyImport_Import, PyPtr, (PyPtr,)),
	# types
	(:PyType_Ready, Cint, (Ptr{CPyTypeObject},)),
	# sys
	(:PySys_SetArgvEx, Cvoid, (Cint, Ptr{Ptr{Cvoid}}, Cint)),
	# object
	(:_PyObject_New=>:PyObject_New, PyPtr, (Ptr{CPyTypeObject},)),
	(:PyObject_RichCompare, PyPtr, (PyPtr,PyPtr,Cint)),
	(:PyObject_RichCompareBool, Cint, (PyPtr,PyPtr,Cint)),
	(:PyObject_IsTrue, Cint, (PyPtr,)),
	(:PyObject_Not, Cint, (PyPtr,)),
	(:PyObject_IsInstance, Cint, (PyPtr, PyPtr)),
	(:PyObject_Type, PyPtr, (PyPtr,)),
	(:PyObject_IsSubclass, Cint, (PyPtr, PyPtr)),
	(:PyObject_Repr, PyPtr, (PyPtr,)),
	(:PyObject_ASCII, PyPtr, (PyPtr,)),
	(:PyObject_Str, PyPtr, (PyPtr,)),
	(:PyObject_Bytes, PyPtr, (PyPtr,)),
	(:PyObject_GetItem, PyPtr, (PyPtr, PyPtr)),
	(:PyObject_SetItem, Cint, (PyPtr, PyPtr, PyPtr)),
	(:PyObject_DelItem, Cint, (PyPtr, PyPtr)),
	(:PyObject_Dir, PyPtr, (PyPtr,)),
	(:PyObject_GetIter, PyPtr, (PyPtr,)),
	(:PyObject_HasAttr, Cint, (PyPtr, PyPtr)),
	(:PyObject_HasAttrString, Cint, (PyPtr, Cstring)),
	(:PyObject_GetAttr, PyPtr, (PyPtr, PyPtr)),
	(:PyObject_GenericGetAttr, PyPtr, (PyPtr, PyPtr)),
	(:PyObject_GetAttrString, PyPtr, (PyPtr, Cstring)),
	(:PyObject_SetAttr, Cint, (PyPtr, PyPtr, PyPtr)),
	(:PyObject_GenericSetAttr, Cint, (PyPtr, PyPtr, PyPtr)),
	(:PyObject_SetAttrString, Cint, (PyPtr, Cstring, PyPtr)),
	(:PyObject_Length, Cssize_t, (PyPtr,)),
	(:PyObject_Call, PyPtr, (PyPtr, PyPtr, PyPtr)),
	(:PyObject_CallObject, PyPtr, (PyPtr, PyPtr)),
	(:PyObject_ClearWeakRefs, Cvoid, (PyPtr,)),
	# number
	(:PyNumber_Check, Cint, (PyPtr,)),
	(:PyNumber_Add, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Subtract, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Multiply, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_MatrixMultiply, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_FloorDivide, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_TrueDivide, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Remainder, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Divmod, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Power, PyPtr, (PyPtr,PyPtr,PyPtr)),
	(:PyNumber_Negative, PyPtr, (PyPtr,)),
	(:PyNumber_Positive, PyPtr, (PyPtr,)),
	(:PyNumber_Absolute, PyPtr, (PyPtr,)),
	(:PyNumber_Invert, PyPtr, (PyPtr,)),
	(:PyNumber_Lshift, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Rshift, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_And, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Xor, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Or, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceAdd, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceSubtract, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceMultiply, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceMatrixMultiply, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceFloorDivide, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceTrueDivide, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceRemainder, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceLshift, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceRshift, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceAnd, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceXor, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_InPlaceOr, PyPtr, (PyPtr, PyPtr)),
	(:PyNumber_Long, PyPtr, (PyPtr,)),
	(:PyNumber_Float, PyPtr, (PyPtr,)),
	(:PyNumber_Index, PyPtr, (PyPtr,)),
	(:PyNumber_ToBase, PyPtr, (PyPtr, Cint)),
	# sequence
	(:PySequence_Check, Cint, (PyPtr,)),
	(:PySequence_Length, Cssize_t, (PyPtr,)),
	(:PySequence_SetItem, Cint, (PyPtr, Cssize_t, PyPtr)),
	(:PySequence_GetItem, PyPtr, (PyPtr, Cssize_t)),
	(:PySequence_Concat, PyPtr, (PyPtr, PyPtr)),
	(:PySequence_Repeat, PyPtr, (PyPtr, Cssize_t)),
	(:PySequence_Contains, Cint, (PyPtr, PyPtr)),
	# mapping
	(:PyMapping_Check, Cint, (PyPtr,)),
	(:PyMapping_Length, Cssize_t, (PyPtr,)),
	(:PyMapping_HasKey, Cint, (PyPtr, PyPtr)),
	(:PyMapping_Keys, PyPtr, (PyPtr,)),
	(:PyMapping_Values, PyPtr, (PyPtr,)),
	(:PyMapping_Items, PyPtr, (PyPtr,)),
	# buffer
	(:PyObject_GetBuffer, Cint, (PyPtr, Ptr{CPy_buffer}, Cint)),
	(:PyBuffer_Release, Cvoid, (Ptr{CPy_buffer},)),
	# iter
	(:PyIter_Next, PyPtr, (PyPtr,)),
	# int
	(:PyLong_FromLong, PyPtr, (Clong,)),
	(:PyLong_FromUnsignedLong, PyPtr, (Culong,)),
	(:PyLong_FromSsize_t, PyPtr, (Cssize_t,)),
	(:PyLong_FromSize_t, PyPtr, (Csize_t,)),
	(:PyLong_FromLongLong, PyPtr, (Clonglong,)),
	(:PyLong_FromUnsignedLongLong, PyPtr, (Culonglong,)),
	(:PyLong_FromDouble, PyPtr, (Cdouble,)),
	(:PyLong_AsLong, Clong, (PyPtr,)),
	(:PyLong_AsLongAndOverflow, Clong, (PyPtr, Ptr{Cint})),
	(:PyLong_AsLongLong, Clonglong, (PyPtr,)),
	(:PyLong_AsLongLongAndOverflow, Clonglong, (PyPtr, Ptr{Cint})),
	(:PyLong_AsSsize_t, Cssize_t, (PyPtr,)),
	(:PyLong_AsUnsignedLong, Culong, (PyPtr,)),
	(:PyLong_AsSize_t, Csize_t, (PyPtr,)),
	(:PyLong_AsUnsignedLongLong, Culonglong, (PyPtr,)),
	(:PyLong_AsUnsignedLongMask, Clong, (PyPtr,)),
	(:PyLong_AsUnsignedLongLongMask, Culonglong, (PyPtr,)),
	(:PyLong_AsDouble, Cdouble, (PyPtr,)),
	# float
	(:PyFloat_FromString, PyPtr, (PyPtr,)),
	(:PyFloat_FromDouble, PyPtr, (Cdouble,)),
	(:PyFloat_AsDouble, Cdouble, (PyPtr,)),
	# complex
	(:PyComplex_FromCComplex, PyPtr, (CPy_complex,)),
	(:PyComplex_FromDoubles, PyPtr, (Cdouble, Cdouble)),
	(:PyComplex_AsCComplex, CPy_complex, (PyPtr,)),
	# bytes
	(:PyBytes_FromStringAndSize, PyPtr, (Ptr{Cchar}, Cssize_t)),
	(:PyBytes_AsStringAndSize, Cint, (PyPtr, Ptr{Ptr{UInt8}}, Ptr{Cssize_t})),
	# str
	(:PyUnicode_AsUTF8String, PyPtr, (PyPtr,)),
	(:PyUnicode_DecodeUTF8, PyPtr, (Ptr{UInt8}, Cssize_t, Ptr{UInt8})),
	# list
	(:PyList_New, PyPtr, (Cssize_t,)),
	(:PyList_SetItem, Cint, (PyPtr, Cssize_t, PyPtr)), # steals
	(:PyList_Insert, Cint, (PyPtr, Cssize_t, PyPtr)),
	(:PyList_Append, Cint, (PyPtr, PyPtr)),
	(:PyList_Reverse, Cint, (PyPtr,)),
	# tuple
	(:PyTuple_New, PyPtr, (Cssize_t,)),
	(:PyTuple_Size, Cssize_t, (PyPtr,)),
	(:PyTuple_SetItem, Cint, (PyPtr, Cssize_t, PyPtr)), # steals
	(:PyTuple_GetItem, PyPtr, (PyPtr, Cssize_t)),
	# dict
	(:PyDict_New, PyPtr, ()),
	(:PyDict_SetItem, Cint, (PyPtr, PyPtr, PyPtr)),
	# slice
	(:PySlice_New, PyPtr, (PyPtr, PyPtr, PyPtr)),
]

for (name, rettype, argtypes) in CPYTHON_FUNCTIONS
	cname, jname = name isa Pair ? name : (name, name)
	jname = Symbol(:C, jname)
	args = [Symbol(:_,i) for i in 1:length(argtypes)]
	cnamesym = QuoteNode(cname)
	@eval @inline function $jname($(args...),) :: $rettype
		ccall(@pysym($cnamesym), $rettype, ($(argtypes...),), $(args...))
	end
end

Base.unsafe_convert(::Type{PyPtr}, x::Ref{CPyTypeObject}) =
	convert(PyPtr, Base.unsafe_convert(Ptr{CPyTypeObject}, x))
