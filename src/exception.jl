#########################################################################
# Wrapper around Python exceptions

struct PyError <: Exception
    msg::String # message string from Julia context, or "" if none

    # info returned by PyErr_Fetch/PyErr_Normalize
    T::PyObject
    val::PyObject
    traceback::PyObject

    # generate a PyError object.  Should normally only be called when
    # PyErr_Occurred returns non-NULL, and clears the Python error
    # indicator.
    function PyError(msg::AbstractString)
        exc = Array{PyPtr}(undef, 3)
        pexc = convert(UInt, pointer(exc))
        # equivalent of passing C pointers &exc[1], &exc[2], &exc[3]:
        ccall((@pysym :PyErr_Fetch), Cvoid, (UInt,UInt,UInt),
              pexc, pexc + sizeof(PyPtr), pexc + 2*sizeof(PyPtr))
        ccall((@pysym :PyErr_NormalizeException), Cvoid, (UInt,UInt,UInt),
              pexc, pexc + sizeof(PyPtr), pexc + 2*sizeof(PyPtr))
        new(msg, PyObject(exc[1]), PyObject(exc[2]), PyObject(exc[3]))
    end

    PyError(msg::AbstractString, e::PyError) = new(msg, e.T, e.val, e.traceback)
end

function show(io::IO, e::PyError)
    print(io, "PyError",
          isempty(e.msg) ? e.msg : string(" (",e.msg,")"),
          " ")

    if ispynull(e.T)
        println(io, "None")
    else
        println(io, pystring(e.T), "\n", pystring(e.val))
    end

    if !ispynull(e.traceback)
        o = pycall(format_traceback, PyObject, e.traceback)
        if !ispynull(o)
            for s in PyVector{AbstractString}(o)
                print(io, s)
            end
        end
    end
end

function Base.showerror(io::IO, e::PyError)
    print(io, "PyCall")
    if ispynull(e.T)
        println(io, " (null)")
    else
        print(io, ": ", e.T.__name__)
        if !ispynull(e.val)
            print(io, ": ", pystr(e.val))
        end
    end
end

#########################################################################
# Conversion of Python exceptions into Julia exceptions

# whether a Python exception has occurred
"""
    pyerr_occurred([t])

True if a Python exception has occurred and (optionally) is of type `t`.
"""
pyerr_occurred() = CPyErr_Occurred() != C_NULL

function pyerr_occurred(t)
    e = CPyErr_Occurred()
    e == C_NULL ? false : pyissubclass(e, t)
end

# call to discard Python exceptions
pyerr_clear() = CPyErr_Clear()

function pyerr_check(msg::AbstractString, val::Any)
    pyerr_occurred() && throw(PyError(msg))
    val # the val argument is there just to pass through to the return value
end

pyerr_check(msg::AbstractString) = pyerr_check(msg, nothing)
pyerr_check() = pyerr_check("")

# extract function name from ccall((@pysym :Foo)...) or ccall(:Foo,...) exprs
callsym(s::Symbol) = s
callsym(s::QuoteNode) = s.value
import Base.Meta.isexpr
callsym(ex::Expr) = isexpr(ex,:macrocall,2) ? callsym(ex.args[2]) : isexpr(ex,:ccall) ? callsym(ex.args[1]) : ex

"""
    _handle_error(msg)

Throw a PyError if available, otherwise throw ErrorException.
This is a hack to manually do the optimization described in
https://github.com/JuliaLang/julia/issues/29688
"""
@noinline function _handle_error(msg)
    pyerr_check(msg)
    error(msg, " failed")
end

# Macros for common pyerr_check("Foo", ccall((@pysym :Foo), ...)) pattern.
macro pycheck(ex)
    :(pyerr_check($(string(callsym(ex))), $(esc(ex))))
end

# Macros to check that ccall((@pysym :Foo), ...) returns value != bad
macro pycheckv(ex, bad)
    quote
        val = $(esc(ex))
        if val == $(esc(bad))
            _handle_error($(string(callsym(ex))))
        end
        val
    end
end
macro pycheckn(ex)
    :(@pycheckv $(esc(ex)) C_NULL)
end
macro pycheckz(ex)
    :(@pycheckv $(esc(ex)) -1)
end

#########################################################################
# Mapping of Julia Exception types to Python exceptions

const pyexc = Dict{DataType, PyPtr}()
const pysymexc = Dict{Symbol, PyPtr}()
mutable struct PyIOError <: Exception end

function pyexc_initialize()
    pyexc[Exception] = @pyglobalobjptr :PyExc_RuntimeError
    pyexc[ErrorException] = @pyglobalobjptr :PyExc_RuntimeError
    pyexc[SystemError] = @pyglobalobjptr :PyExc_SystemError
    pyexc[TypeError] = @pyglobalobjptr :PyExc_TypeError
    pyexc[Meta.ParseError] = @pyglobalobjptr :PyExc_SyntaxError
    pyexc[ArgumentError] = @pyglobalobjptr :PyExc_ValueError
    pyexc[KeyError] = @pyglobalobjptr :PyExc_KeyError
    pyexc[LoadError] = @pyglobalobjptr :PyExc_ImportError
    pyexc[MethodError] = @pyglobalobjptr :PyExc_RuntimeError
    pyexc[EOFError] = @pyglobalobjptr :PyExc_EOFError
    pyexc[BoundsError] = @pyglobalobjptr :PyExc_IndexError
    pyexc[DivideError] = @pyglobalobjptr :PyExc_ZeroDivisionError
    pyexc[DomainError] = @pyglobalobjptr :PyExc_RuntimeError
    pyexc[OverflowError] = @pyglobalobjptr :PyExc_OverflowError
    pyexc[InexactError] = @pyglobalobjptr :PyExc_ArithmeticError
    pyexc[OutOfMemoryError] = @pyglobalobjptr :PyExc_MemoryError
    pyexc[StackOverflowError] = @pyglobalobjptr :PyExc_MemoryError
    pyexc[UndefRefError] = @pyglobalobjptr :PyExc_RuntimeError
    pyexc[InterruptException] = @pyglobalobjptr :PyExc_KeyboardInterrupt
    pyexc[PyIOError] = @pyglobalobjptr :PyExc_IOError

    pysymexc[:RuntimeError] = @pyglobalobjptr :PyExc_RuntimeError
    pysymexc[:SystemError] = @pyglobalobjptr :PyExc_SystemError
    pysymexc[:TypeError] = @pyglobalobjptr :PyExc_TypeError
    pysymexc[:SyntaxError] = @pyglobalobjptr :PyExc_SyntaxError
    pysymexc[:ValueError] = @pyglobalobjptr :PyExc_ValueError
    pysymexc[:KeyError] = @pyglobalobjptr :PyExc_KeyError
    pysymexc[:ImportError] = @pyglobalobjptr :PyExc_ImportError
    pysymexc[:EOFError] = @pyglobalobjptr :PyExc_EOFError
    pysymexc[:IndexError] = @pyglobalobjptr :PyExc_IndexError
    pysymexc[:ZeroDivisionError] = @pyglobalobjptr :PyExc_ZeroDivisionError
    pysymexc[:OverflowError] = @pyglobalobjptr :PyExc_OverflowError
    pysymexc[:ArithmeticError] = @pyglobalobjptr :PyExc_ArithmeticError
    pysymexc[:MemoryError] = @pyglobalobjptr :PyExc_MemoryError
    pysymexc[:KeyboardInterrupt] = @pyglobalobjptr :PyExc_KeyboardInterrupt
    pysymexc[:IOError] = @pyglobalobjptr :PyExc_IOError
    pysymexc[:AttributeError] = @pyglobalobjptr :PyExc_AttributeError
end

_showerror_string(io::IO, e, ::Nothing) = showerror(io, e)
_showerror_string(io::IO, e, bt) = showerror(io, e, bt)

# bt argument defaults to nothing, to delay dispatching on the presence of a
# backtrace until after the try-catch block
"""
    showerror_string(e) :: String

Convert output of `showerror` to a `String`.  Since this function may
be called via Python C-API, it tries to not throw at all cost.
"""
function showerror_string(e::T, bt = nothing) where {T}
    try
        io = IOBuffer()
        _showerror_string(io, e, bt)
        return String(take!(io))
    catch
        try
            return """
                   $e
                   ERROR: showerror(::IO, ::$T) failed!"""
        catch
            try
                return """
                       $T
                       ERROR: showerror(::IO, ::$T) failed!
                       ERROR: string(::$T) failed!"""
            catch
                name = try
                    io = IOBuffer()
                    Base.show_datatype(io, T)
                    String(take!(io))
                catch
                    "_UNKNOWN_TYPE_"
                end
                return """
                       Unprintable error.
                       ERROR: showerror(::IO, ::$name) failed!
                       ERROR: string(::$name) failed!
                       ERROR: string($name) failed!"""
            end
        end
    end
end

function pyraise(e::Exception, bt = nothing)
    eT = typeof(e)
    pyeT = haskey(pyexc::Dict, eT) ? pyexc[eT] : pyexc[Exception]
    pyraise(pyeT, e, bt)
end

function pyraise(T::PyPtr, e::Exception, bt=nothing)
    pyraise(T, string("Julia exception: ", showerror_string(e, bt)))
end

function pyraise(T::Symbol, msg::AbstractString)
    pyraise(pysymexc[T], msg)
end

function pyraise(T::PyPtr, msg::AbstractString)
    ccall(@pysym(:PyErr_SetString), Cvoid, (PyPtr, Cstring), T, msg)
end

# Second argument allows for backtraces passed to `pyraise` to be ignored.
function pyraise(e::PyError, ::Vector = [])
    ccall((@pysym :PyErr_Restore), Cvoid, (PyPtr, PyPtr, PyPtr),
          e.T, e.val, e.traceback)
    # refs were stolen
    setfield!(e.T, :o, PyPtr_NULL)
    setfield!(e.val, :o, PyPtr_NULL)
    setfield!(e.traceback, :o, PyPtr_NULL)
end

"""
    @pyraise e

Throw the exception `e` to Python, attaching a backtrace.  This macro should only be
used in a `catch` block so that `catch_backtrace()` is valid.
"""
macro pyraise(e)
    :(pyraise($(esc(e)), catch_backtrace()))
end