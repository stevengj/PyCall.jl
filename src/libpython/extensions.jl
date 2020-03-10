# Extensions to the C API
#
# These functions will only raise exceptions arising from julia. Python exceptions are propagated by return value as usual.
#
# Functions `CPy<type>_From(x)` convert `x` to a python `type`. If `x` is a `PyPtr`, this is equivalent to `<type>(x)` in python. Otherwise, it typically is a wrapper for one of the `CPy<type>_From<ctype>` functions in the C API. Returns `C_NULL` on error.
#
# Functions `CPy<type>_As(T, x)` convert `x` (which should be a `PyPtr` of python type `type`) to a `T`. Returns `nothing` on error.
#
# `CPyObject_From(x)` defines the default conversion from julia to python.



"""
	CPyDict_FromIterator([fk=identity, fv=identity,] x)

A python `dict` whose keys are `fk(k)` and values are `fv(v)` for `(k,v) ∈ x`.

The keys and values must be `PyPtr`. This steals references, so the elements must be new references.
"""
function CPyDict_FromIterator(fk, fv, x) :: PyPtr
	t = CPyDict_New()
	t == C_NULL && (return C_NULL)
	for (k, v) in x
		kk = fk(k) :: PyPtr
		kk == C_NULL && (CPy_DecRef(t); return C_NULL)
		vv = fv(v) :: PyPtr
		vv == C_NULL && (CPy_DecRef(kk); CPy_DecRef(t); return C_NULL)
		e = CPyDict_SetItem(t, kk, vv)
		CPy_DecRef(kk)
		CPy_DecRef(vv)
		e == -1 && (CPy_DecRef(t); return C_NULL)
	end
	t
end

CPyDict_FromIterator(x) =
	CPyDict_FromIterator(identity, identity, x)

function CPyDict_From(x::PyPtr) :: PyPtr
	CPyObject_CallFunction(CPyDict_Type[], x)
end





"""
    CPyTuple_FromIterator([f=identity,] x)

A python `tuple` whose elements come from `map(f, x)`.

The length of `x` must be known. The elements must be `PyPtr`. This steals references, so the elements must be new references.
"""
function CPyTuple_FromIterator(f, x) :: PyPtr
	t = CPyTuple_New(length(x))
	t == C_NULL && (return C_NULL)
	i = 0
	for y in x
	    z = f(y) :: PyPtr
	    z == C_NULL && (CPy_DecRef(t); return C_NULL)
	    e = CPyTuple_SetItem(t, i, z)
	    e == -1 && (CPy_DecRef(t); return C_NULL)
	    i += 1
	end
	t
end

CPyTuple_FromIterator(x) = CPyTuple_FromIterator(identity, x)

function CPyTuple_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyTuple_Type[], x)
end








"""
    CPyList_FromIterator([f=identity,] x)

A python `list` whose elements come from `map(f, x)`.

The elements must be `PyPtr`. This steals references, so the elements must be new references.
"""
function CPyList_FromIterator(f, x) :: PyPtr
	# potential optimization: check if the length of x is known in advance
	t = CPyList_New(0)
	t == C_NULL && (return C_NULL)
	for y in x
	    z = f(y) :: PyPtr
	    z == C_NULL && (CPy_DecRef(t); return C_NULL)
	    e = CPyList_Append(t, z)
	    e == -1 && (CPy_DecRef(t); return C_NULL)
	end
	t
end

CPyList_FromIterator(x) = CPyList_FromIterator(identity, x)

function CPyList_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyList_Type[], x)
end



function CPyUnicode_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyUnicode_Type[], x)
end

function CPyUnicode_From(x::String)::PyPtr
	CPyUnicode_DecodeUTF8(Base.unsafe_convert(Ptr{UInt8}, x), sizeof(x), C_NULL)
end

function CPyUnicode_From(x::AbstractString)::PyPtr
	CPyUnicode_From(convert(String, x))
end

function CPyUnicode_As(::Type{T}, x) where {T<:AbstractString}
	b = CPyUnicode_AsUTF8String(x)
	b == C_NULL && (return nothing)
	buf = Ref{Ptr{UInt8}}(C_NULL)
	len = Ref{Cssize_t}(0)
	z = CPyBytes_AsStringAndSize(b, buf, len)
	z == -1 && (CPy_DecRef(b); return nothing)
	s = unsafe_string(buf[], len[])
	CPy_DecRef(b)
	convert(T, s)
end





function CPyBool_From(x::PyPtr)::PyPtr
	r = CPyObject_IsTrue(x)
	r == -1 && (return C_NULL)
	CPyBool_From(r == 1)
end

function CPyBool_From(x::Bool)::PyPtr
	r = x ? CPy_True[] : CPy_False[]
	CPy_IncRef(r)
	r
end




function CPyLong_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyLong_Type[], x)
end

function CPyLong_From(x::AbstractString)::PyPtr
	y = CPyUnicode_From(x)
	y == C_NULL && (return C_NULL)
	z = CPyLong_From(y)
	CPy_DecRef(y)
	z
end

function CPyLong_From(x::Real)::PyPtr
	y = CPyFloat_From(x)
	y == C_NULL && (return C_NULL)
	z = CPyLong_From(y)
	CPy_DecRef(y)
	z
end

function CPyLong_From(x::Complex)::PyPtr
	y = CPyComplex_From(x)
	y == C_NULL && (return C_NULL)
	z = CPyLong_From(y)
	CPy_DecRef(y)
	z
end

function CPyLong_From(x::Number)::PyPtr
	CPyLong_From(convert(Real, x)::Real)
end

function CPyLong_From(x)::PyPtr
	CPyLong_From(convert(Number, x)::Number)
end

@static if pyversion < v"3"
	function CPyLong_From(x::T) where {T<:Integer}
		if isbitstype(T)
			if T <: Unsigned
				if sizeof(T) ≤ sizeof(Csize_t)
					return CPyInt_FromSize_t(x)
				end
			else
				if sizeof(T) ≤ sizeof(Cssize_t)
					return CPyInt_FromSsize_t(x)
				end
			end
		end
		CPyLong_From(string(x))
	end
else
	function CPyLong_From(x::T) where {T<:Integer}
		if isbitstype(T)
			if T <: Unsigned
				if sizeof(T) ≤ sizeof(Culonglong)
					return CPyLong_FromUnsignedLongLong(x)
				end
			else
				if sizeof(T) ≤ sizeof(Clonglong)
					return CPyLong_FromLongLong(x)
				end
			end
		end
		CPyLong_From(string(x))
	end
end

@static if pyversion < v"3"
    function CPyLong_As(::Type{T}, o) where {T<:Integer}
    	val = CPyInt_AsSsize_t(o)
    	if val == -1 && CPyErr_Occurred() != C_NULL
    		CPyErr_Clear()
    		convert(T, convert(BigInt, o))
    	else
    		convert(T, val)
    	end
    end
elseif pyversion < v"3.2"
	function CPyLong_As(::Type{T}, o) where {T<:Integer}
		val = CPyLong_AsLongLong(o)
		if val == -1 && CPyErr_Occurred() != C_NULL
			CPyErr_Clear()
			convert(T, convert(BigInt, o))
		else
	        convert(T, val)
	    end
    end
else
    function CPyLong_As(::Type{T}, o) where {T<:Integer}
        overflow = Ref{Cint}()
        val = CPyLong_AsLongLongAndOverflow(o, overflow)
        val == -1 && CPyErr_Occurred() != C_NULL && (return nothing)
        if iszero(overflow[])
        	convert(T, val)
        else
        	convert(T, convert(BigInt, o))
        end
    end
end

function CPyLong_As(::Type{BigInt}, o)
	s = CPyObject_Str(String, o)
	s===nothing && return nothing
	parse(BigInt, s)
end




function CPyFloat_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyFloat_Type[], x)
end

function CPyFloat_From(x::Float64)::PyPtr
	CPyFloat_FromDouble(x)
end

function CPyFloat_From(x::Real)::PyPtr
	CPyFloat_From(convert(Float64, x))
end

function CPyFloat_From(x::Number)::PyPtr
	CPyFloat_From(convert(Real, x))
end

function CPyFloat_From(x)::PyPtr
	CPyFloat_From(convert(Number, x))
end

function CPyFloat_From(x::AbstractString)::PyPtr
	y = CPyUnicode_From(x)
	y == C_NULL && (return C_NULL)
	z = CPyFloat_From(y)
	CPy_DecRef(y)
	z
end

function CPyFloat_As(::Type{T}, x) where {T<:Number}
	y = CPyFloat_AsDouble(x)
	y == -1 && CPyErr_Occurred() != C_NULL && (return nothing)
	convert(T, y)
end




function CPyComplex_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyComplex_Type[], x)
end

function CPyComplex_From(x::Complex)::PyPtr
	CPyComplex_FromDoubles(real(x), imag(x))
end

function CPyComplex_From(x::Number)::PyPtr
	y = CPyFloat_From(x)
	y == C_NULL && (return C_NULL)
	z = CPyComplex_From(y)
	CPy_DecRef(y)
	z
end

function CPyComplex_As(::Type{T}, x) where {T<:Number}
	y = CPyComplex_AsCComplex(x)
	CPyErr_Occurred() == C_NULL || (return nothing)
	convert(T, Complex(y.real, y.imag))
end



function CPyBytes_From(x::PyPtr)::PyPtr
	CPyObject_CallFunction(CPyBytes_Type[], x)
end

function CPyBytes_From(x::AbstractVector{UInt8})::PyPtr
	# try to avoid copying x
	try
		if stride(x, 1) == 1
			ptr = Base.unsafe_convert(Ptr{UInt8}, x)
			sz = sizeof(x)
			return CPyBytes_FromStringAndSize(ptr, sz)
		end
	catch
	end
	y = convert(Vector, x)
	ptr = Base.unsafe_convert(Ptr{UInt8}, y)
	sz = sizeof(y)
	return CPyBytes_FromStringAndSize(ptr, sz)
end





function CPyObject_Repr(::Type{T}, x) where {T<:AbstractString}
	y = CPyObject_Repr(x)
	y == C_NULL && (return nothing)
	s = CPyUnicode_As(T, y)
	CPy_DecRef(y)
	s
end

function CPyObject_ASCII(::Type{T}, x) where {T<:AbstractString}
	y = CPyObject_ASCII(x)
	y == C_NULL && (return nothing)
	s = CPyUnicode_As(T, y)
	CPy_DecRef(y)
	s
end

function CPyObject_Str(::Type{T}, x) where {T<:AbstractString}
	y = CPyObject_Str(x)
	y == C_NULL && (return nothing)
	s = CPyUnicode_As(T, y)
	CPy_DecRef(y)
	s
end


function CPyObject_As end

function CPyObject_As(::Type{Nothing}, x)
	nothing
end

function CPyObject_As(::Type{Missing}, x)
	missing
end

function CPyObject_As(::Type{Bool}, x)
	r = CPyObject_IsTrue(x)
	r == -1 ? nothing : r == 1
end

function CPyObject_As(::Type{T}, x) where {T<:AbstractString}
	CPyObject_Str(T, x)
end

function CPyObject_As(::Type{T}, x) where {T<:Real}
	CPyFloat_As(T, x)
end




function CPyObject_From(x::PyPtr)::PyPtr
	x == C_NULL || CPy_IncRef(x)
	return x
end

function CPyObject_From(x::Integer)::PyPtr
	CPyLong_From(x)
end

function CPyObject_From(x::Real)::PyPtr
	CPyFloat_From(x)
end

function CPyObject_From(x::Complex)::PyPtr
	CPyComplex_From(x)
end

function CPyObject_From(x::Nothing)::PyPtr
	CPy_None_NewRef()
end

function CPyObject_From(x::Bool)::PyPtr
	CPyBool_From(x)
end

function CPyObject_From(x::AbstractString)::PyPtr
	CPyUnicode_From(x)
end

function CPyObject_From(x::Symbol)::PyPtr
	CPyUnicode_From(string(x))
end

function CPyObject_From(x::Tuple)::PyPtr
	CPyTuple_FromIterator(CPyObject_From, x)
end

function CPyObject_From(x::AbstractDict)::PyPtr
	CPyDict_FromIterator(CPyObject_From, CPyObject_From, pairs(x))
end

function CPyObject_From(x::AbstractVector)::PyPtr
	CPyList_FromIterator(CPyObject_From, x)
end

function CPyObject_From(x::AbstractSet)::PyPtr
	CPySet_FromIterator(CPyObject_From, x)
end





function CPyObject_CallFunction(f, args...; kwargs...)::PyPtr
	if isempty(kwargs)
		_args = CPyTuple_FromIterator(CPyObject_From, args)
		_args == C_NULL && (return C_NULL)
		r = CPyObject_CallObject(f, _args)
		CPy_DecRef(_args)
		return r
	else
		_args = CPyTuple_FromIterator(CPyObject_From, args)
		_args == C_NULL && (return C_NULL)
		_kwargs = CPyDict_FromIterator(CPyObject_From, CPyObject_From, kwargs)
		_kwargs == C_NULL && (CPy_DecRef(_args); return C_NULL)
		r = CPyObject_Call(f, _args, _kwargs)
		CPy_DecRef(_args)
		CPy_DecRef(_kwargs)
		return r
	end
end

function cpyargdata(arg)
	# parse out the default
	if arg isa Expr && arg.head == :(=)
		lhs, dflt = arg.args
		dflt = Some(dflt)
	else
		lhs = arg
		dflt = nothing
	end
	# parse out the type
	if lhs isa Expr && lhs.head == :(::)
		argname, typ = lhs.args
	else
		argname = lhs
		typ = :PyPtr
	end
	# check the argname
	argname isa Symbol || error("invalid argument: $arg")
	argname = argname==:_ ? nothing : argname
	# done
	(name=argname, typ=typ, dflt=dflt)
end

function cpyargsdata(args)
	argsdata = map(cpyargdata, args)
	# number of required arguments
	numreq = 0
	for arg in argsdata
		if arg.dflt===nothing
			numreq += 1
		else
			break
		end
	end
	# (minimum) number of positional arguments
	numpos = 0
	for arg in argsdata
		if arg.name == nothing
			numpos += 1
		else
			break
		end
	end
	#
	(args=argsdata, nreq=numreq, npos=numpos)
end

cpyargparse(::Type{PyPtr}, x::PyPtr) = (CPy_IncRef(x); x)
cpyargparse(::Type{T}, x::PyPtr) where {T<:Integer} =
	CPyLong_As(T, x)
cpyargparse(::Type{T}, x::PyPtr) where {T<:Real} =
	CPyFloat_As(T, x)
cpyargparse(::Type{T}, x::PyPtr) where {T<:AbstractString} =
	CPyUnicode_As(T, x)

cpyargfree(x) = nothing
cpyargfree(x::PyPtr) = CPy_DecRef(x)

function _cpyargsparse(t, k, args)
	data = cpyargsdata(args)
	tnames = [Symbol(:t, i-1) for i in 1:length(args)]
	anames = [Symbol(:x, i-1) for i in 1:length(args)]
	body = quote
		# check the length
		len = CPyTuple_Size(t)
		len == -1 && @goto(ERROR)
		len ≤ $(length(args)) || @goto(ERROR) # TODO: set an error
		# default PyPtr values (these are borrowed references)
		$([:($n :: PyPtr = C_NULL) for n in tnames]...)
		# parse the tuple
		$([:(len ≥ $i && ($n = CPyTuple_GetItem(t, $(i-1)); $n == C_NULL && @goto(ERROR))) for (i,(a,n)) in enumerate(zip(data.args, tnames))]...)
		# parse the kwargs
		$(k===nothing ? nothing : error("parsing keywords not implemented"))
		# extra parsing
		$([quote
			$n =
				if $t == C_NULL
					$(a.dflt===nothing ? :(#=TODO: set an error=# nothing) : :(Some($(esc(something(a.dflt))))))
				else
					cpyargparse($(esc(a.typ)), $t)
				end
			$n === nothing && @goto($(Symbol(:ERROR_,n)))
		end for (a,n,t) in zip(data.args, anames, tnames)]...)
		# return the tuple
		return ($([:(something($n)) for n in anames]...),)
		# errors
		$([:(cpyargfree($n); @label($(Symbol(:ERROR_,n)))) for n in reverse(anames)]...)
		@label ERROR
		return nothing
	end
	:((function (t, k); $body; end)($(esc(t)), $(k===nothing ? C_NULL : esc(k))))
end

"""
	@CPyArg_ParseTuple(args, NAME::TYPE=DEFAULT)

Similar to `@CPyArg_ParseTupleAndKeywords` but only takes an `args` tuple.

Note that the `NAME` is ignored in this case.
"""
macro CPyArg_ParseTuple(t, args...)
	_cpyargsparse(t, nothing, args)
end

"""
	@CPyArg_ParseTupleAndKeywords(args, kwargs, NAME::TYPE=DEFAULT, ...)

Parse `args` (a `PyPtr` to a tuple) and `kwargs` (a `PyPtr` to a dict) according to the argument specifiers of the form `NAME::TYPE=DEFAULT`. Return a tuple whose entries are of types `TYPE`, or `nothing` on error.

The `NAME` may be `_` to signify a positional-only argument. Otherwise, it is the name of a possibly-keyword argument.

The `TYPE` is optional, and defaults to `PyPtr`. Currently it can be one of `PyPtr`, `<:Integer`, `<:Real`, `<:AbstractString`.

The `DEFAULT` is optional. When not specified, the argument is required.
"""
macro CPyArg_ParseTupleAndKeywords(t, k, args...)
	_cpyargsparse(t, k, args...)
end