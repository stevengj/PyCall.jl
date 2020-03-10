# Passing Julia callback functions to Python routines.
#
# Note that this will typically involve two functions: the
# desired Julia function/closure, and a top-level C-callable
# wrapper function used with PyCFunction_NewEx -- the latter
# is called from Python and calls the former as needed.

################################################################

# To pass an arbitrary Julia object to Python, we wrap it
# in a jlwrap Python class, where jlwrap.__call__
# executes the pyjlwrap_call function in Julia, which
# in turn fetches the actual Julia value from the python wrapper
# and calls it.

# convert Python args to Julia; overridden below for a FuncWrapper type
# that allows the user to specify the argument types.
julia_args(f, args) = convert(PyAny, args)
julia_kwarg(f, kw, arg) = convert(PyAny, arg)

################################################################
# allow the user to convert a Julia function into a Python
# function with specified argument types, both to give more control
# and to avoid the overhead of type introspection.

struct FuncWrapper{T,F}
    f::F
    kwargs::Dict{Symbol,Any}
end
(f::FuncWrapper)(args...; kws...) = f.f(args...; kws...)
julia_args(f::FuncWrapper{T}, args) where {T} = convert(T, args)
julia_kwarg(f::FuncWrapper, kw, arg) = convert(get(f.kwargs, kw, PyAny), arg)

FuncWrapper(f, kwargs, argtypes::Type) = FuncWrapper{argtypes,typeof(f)}(f, kwargs)

"""
    pyfunction(f, argtypes...; kwtypes...)

Create a Python object that wraps around the Julia function (or callable
object) `f`.   Unlike `PyObject(f)`, this allows you to specify the argument
types that the Julia function expects — giving you more control and potentially
better performance.

`kwtypes...` should be a set of `somekeyword=SomeType` arguments giving
the desired Julia type for each keyword `somekeyword`.  Unspecified keywords
are converted to `PyAny` (i.e. auto-detected) by default.

The return value `ret = f(...)` is still converted back to a Python object by
`PyObject(ret)`.   If you want a different return-type conversion than the default
of `PyObject(ret)`, you can instead call `pyfunctionret`.
"""
function pyfunction(f, argtypes...; kwtypes...)
    kwdict = Dict{Symbol,Any}(k => v for (k,v) in kwtypes)
    return pyjlwrap_new(FuncWrapper(f, kwdict, Tuple{argtypes...}))
end

"""
    pyfunctionret(f, returntype, argtypes...; kwtypes...)

Like `pyfunction`, but also lets you specify the `returntype` for
conversion back to Python.   In particular, if `ret = f(...)` is
the return value of `f`, then it is converted to Python via
`PyObject(returntype(ret))`.

If `returntype` is `Any`, then `ret` is not converted to a "native"
Python type at all, and is instead converted to a "wrapped" Julia
object in Python.  If `returntype` is `nothing`, then the return value
is discarded and `nothing` is returned to Python.
"""
function pyfunctionret(f, returntype, argtypes...; kwtypes...)
    if returntype === Any
        return pyfunction((args...; kws...) -> pyjlwrap_new(f(args...; kws...)),
                          argtypes...; kwtypes...)
    elseif returntype === nothing
        return pyfunction((args...; kws...) -> begin f(args...; kws...); nothing; end,
                          argtypes...; kwtypes...)
    else
        return pyfunction((args...; kws...) -> returntype(f(args...; kws...)),
                          argtypes...; kwtypes...)
    end
end
