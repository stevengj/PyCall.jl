"""
Low-level version of `pycall!(ret, o, ...; kwargs...)`
Sets `ret.o` to the result of the call, and returns `ret::PyObject`
"""
function _pycall!(ret::PyObject, o::Union{PyObject,PyPtr}, args, kwargs)
    if isempty(kwargs)
        kw = C_NULL
    else
        kw = PyObject(Dict{AbstractString, Any}([Pair(string(k), v) for (k, v) in kwargs]))
    end
    _pycall!(ret, o, args, length(args), kw)
end

"""
Low-level version of `pycall!(ret, o, ...)` for when `kw` is already in python
friendly format but you don't have the python tuple to hold the arguments
(`pyargsptr`). Sets `ret.o` to the result of the call, and returns `ret::PyObject`.
"""
function _pycall!(ret::PyObject, o::Union{PyObject,PyPtr}, args, nargs::Int=length(args),
                  kw::Union{Ptr{Cvoid}, PyObject}=C_NULL)
    pyargsptr = @pycheckn ccall((@pysym :PyTuple_New), PyPtr, (Int,), nargs)
    try
        for i = 1:nargs
            pyarg = PyObject(args[i])
            pyincref(pyarg) # PyTuple_SetItem steals the reference
            @pycheckz ccall((@pysym :PyTuple_SetItem), Cint,
                                (PyPtr,Int,PyPtr), pyargsptr, i-1, pyarg)
        end
        return __pycall!(ret, pyargsptr, o, kw) #::PyObject
    finally
        pydecref_(pyargsptr)
    end
end

"""
Lowest level version of  `pycall!(ret, o, ...)`, assumes `pyargsptr` and `kw`
have all their args set to Python values, so we can just call the function `o`.
Sets `ret.o` to the result of the call, and returns `ret::PyObject`.
"""
function __pycall!(ret::PyObject, pyargsptr::PyPtr, o::Union{PyObject,PyPtr},
  kw::Union{Ptr{Cvoid}, PyObject})
    disable_sigint() do
        retptr = @pycheckn ccall((@pysym :PyObject_Call), PyPtr, (PyPtr,PyPtr,PyPtr), o,
                        pyargsptr, kw)
        pydecref_(ret)
        setfield!(ret, :o, retptr)
    end
    return ret #::PyObject
end

"""
```
pycall!(ret::PyObject, o::Union{PyObject,PyPtr}, returntype::Type, args...; kwargs...)
```
Set `ret` to the result of `pycall(o, returntype, args...; kwargs)` and return
`convert(returntype, ret)`.
Avoids allocating an extra PyObject for `ret`. See `pycall` for other details.
"""
pycall!(ret::PyObject, o::Union{PyObject,PyPtr}, returntype::TypeTuple, args...; kwargs...) =
    return convert(returntype, _pycall!(ret, o, args, kwargs))

function pycall!(ret::PyObject, o::T, returntype::Type{PyObject}, args...; kwargs...) where
  T<:Union{PyObject,PyPtr}
    return _pycall!(ret, o, args, kwargs)
end

pycall!(ret::PyObject, o::Union{PyObject,PyPtr}, ::Type{PyAny}, args...; kwargs...) =
    return convert(PyAny, _pycall!(ret, o, args, kwargs))

"""
```
pycall(o::Union{PyObject,PyPtr}, returntype::TypeTuple, args...; kwargs...)
```
Call the given Python function (typically looked up from a module) with the
given args... (of standard Julia types which are converted automatically to the
corresponding Python types if possible), converting the return value to
returntype (use a returntype of PyObject to return the unconverted Python object
reference, or of PyAny to request an automated conversion)
"""
pycall(o::Union{PyObject,PyPtr}, returntype::TypeTuple, args...; kwargs...) =
    return convert(returntype, _pycall!(PyNULL(), o, args, kwargs))::returntype

pycall(o::Union{PyObject,PyPtr}, ::Type{PyAny}, args...; kwargs...) =
    return convert(PyAny, _pycall!(PyNULL(), o, args, kwargs))

(o::PyObject)(args...; kwargs...) =
    return convert(PyAny, _pycall!(PyNULL(), o, args, kwargs))

PyAny(o::PyObject) = convert(PyAny, o)

"""
    @pycall func(args...)::T

Convenience macro which turns `func(args...)::T` into pycall(func, T, args...)
"""
macro pycall(ex)
    if !(isexpr(ex,:(::)) && isexpr(ex.args[1],:call))
        throw(ArgumentError("Usage: @pycall func(args...)::T"))
    end
    func = ex.args[1].args[1]
    args, kwargs = ex.args[1].args[2:end], []
    if !isempty(args) && isexpr(args[1],:parameters)
        kwargs, args = args[1], args[2:end]
    end
    T = ex.args[2]
    :(pycall($(map(esc,[kwargs; func; T; args])...)))
end
