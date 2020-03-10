"""
    pystr(o::PyObject)

Return a string representation of `o` corresponding to `str(o)` in Python.
"""
pystr(args...; kwargs...) =
    pystr(AbstractString, args...; kwargs...)
pystr(T::Type{<:AbstractString}, args...; kwargs...) =
    convert(T, pystr(PyObject, args...; kwargs...))
pystr(::Type{PyObject}, o) =
    PyObject(@pycheckn ccall(@pysym(:PyObject_Str), PyPtr, (PyPtr,), PyObject(o)))
pystr(::Type{PyObject}, o::AbstractString="") =
    convertpystr(o)

"""
    pyrepr(o::PyObject)

Return a string representation of `o` corresponding to `repr(o)` in Python.
"""
pyrepr(o) =
    pystr(AbstractString, o)
pyrepr(::Type{T}, o) where {T<:AbstractString} =
    convert(T, pyrepr(PyObject, o))
pyrepr(::Type{PyObject}, o) =
    PyObject(@pycheckn ccall(@pysym(:PyObject_Repr), PyPtr, (PyPtr,), PyObject(o)))

"""
    pyisinstance(o::PyObject, t::PyObject)

True if `o` is an instance of `t`, corresponding to `isinstance(o,t)` in Python.
"""
pyisinstance(o, t) =
    pyisinstance(Bool, o, t)
pyisinstance(::Type{Bool}, o, t) =
    pyisinstance(Bool, PyObject(o), PyObject(t))
pyisinstance(::Type{Bool}, o::PyObject, t::PyObject) =
    !ispynull(t) && ccall((@pysym :PyObject_IsInstance), Cint, (PyPtr,PyPtr), o, t) == 1
pyisinstance(::Type{Bool}, o::PyObject, t::Union{Ptr{Cvoid},PyPtr}) =
    t != C_NULL && ccall((@pysym :PyObject_IsInstance), Cint, (PyPtr,PyPtr), o, t) == 1
pyisinstance(::Type{PyObject}, o, t) =
    convertpybool(pyisinstance(Bool, o, t))

"""
    pyistrue(o::PyObject)

True if `o` is considered to be true, corresponding to `not not o` in Python.
"""
pyistrue(o::PyObject) =
    pyistrue(Bool, o)
pyistrue(::Type{Bool}, o::PyObject) =
    (@pycheckz ccall(@pysym(:PyObject_IsTrue), Cint, (PyPtr,), o)) == 1
pyistrue(::Type{PyObject}, o) =
    convertpybool(pyistrue(Bool, o))

"""
    pynot(o::PyObject)

True if `o` is not considered to be true, corresponding to `not o` in Python.
"""
pynot(o::PyObject) =
    pynot(Bool, o)
pynot(::Type{Bool}, o::PyObject) =
    (@pycheckz ccall(@pysym(:PyObject_Not), Cint, (PyPtr,), o)) == 1
pynot(::Type{PyObject}, o) =
    convertpybool(pynot(Bool, o))

"""
    pyint(o::PyObject)
"""
pyint(args...; kwargs...) =
    pyint(PyObject, args...; kwargs...)
pyint(T::Type, args...; kwargs...) =
    pycall(pybuiltin("int"), T, args...; kwargs...)
pyint(::Type{PyObject}, o::Integer=0) =
    convertpyint(o)

"""
    pybool(o::PyObject)
"""
pybool(args...; kwargs...) =
    pybool(PyObject, args...; kwargs...)
pybool(T::Type, args...; kwargs...) =
    pycall(pybuiltin("bool"), T, args...; kwargs...)
pybool(::Type{PyObject}, o::Bool=false) =
    convertpybool(o)

"""
    pystring(o::PyObject)

Return a string representation of `o`.  Normally, this corresponds to `repr(o)`
in Python, but unlike `repr` it should never fail (falling back to `str` or to
printing the raw pointer if necessary).
"""
function pystring(o::PyObject)
    if ispynull(o)
        return "NULL"
    else
        s = ccall((@pysym :PyObject_Repr), PyPtr, (PyPtr,), o)
        if (s == C_NULL)
            pyerr_clear()
            s = ccall((@pysym :PyObject_Str), PyPtr, (PyPtr,), o)
            if (s == C_NULL)
                pyerr_clear()
                return string(PyPtr(o))
            end
        end
        return convert(AbstractString, PyObject(s))
    end
end
