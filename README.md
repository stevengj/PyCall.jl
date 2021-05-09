# Calling Python functions from the Julia language

[![Test with system Python](https://github.com/JuliaPy/PyCall.jl/workflows/Test%20with%20system%20Python/badge.svg)](https://github.com/JuliaPy/PyCall.jl/actions?query=workflow%3A%22Test+with+system+Python%22)
[![Test with conda](https://github.com/JuliaPy/PyCall.jl/workflows/Test%20with%20conda/badge.svg)](https://github.com/JuliaPy/PyCall.jl/actions?query=workflow%3A%22Test+with+conda%22)
[![PkgEval](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/P/PyCall.named.svg)](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/P/PyCall.html)
[![Coverage](https://codecov.io/gh/JuliaPy/PyCall.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaPy/PyCall.jl)

This package provides the ability to directly call and **fully
interoperate with Python** from [the Julia
language](https://julialang.org/).  You can import arbitrary Python
modules from Julia, call Python functions (with automatic conversion
of types between Julia and Python), define Python classes from Julia
methods, and share large data structures between Julia and Python
without copying them.

## Installation

Within Julia, just use the package manager to run `Pkg.add("PyCall")` to
install the files. Julia 0.7 or later is required.

The latest development version of PyCall is available from
<https://github.com/JuliaPy/PyCall.jl>.  If you want to switch to
this after installing the package, run `Pkg.checkout("PyCall"); Pkg.build("PyCall")`.

By default on Mac and Windows systems, `Pkg.add("PyCall")`
or `Pkg.build("PyCall")` will use the
[Conda.jl](https://github.com/Luthaf/Conda.jl) package to install a
minimal Python distribution (via
[Miniconda](https://conda.io/projects/conda/en/latest/glossary.html#miniconda-glossary))
that is private to Julia (not in your `PATH`).  You can use the `Conda` Julia
package to install more Python packages, and `import Conda` to print
the `Conda.PYTHONDIR` directory where `python` was installed.
On GNU/Linux systems, PyCall will default to using
the `python3` program (if any, otherwise `python`) in your PATH.

The advantage of a Conda-based configuration is particularly
compelling if you are installing PyCall in order to use packages like
[PyPlot.jl](https://github.com/JuliaPy/PyPlot.jl) or
[SymPy.jl](https://github.com/JuliaPy/SymPy.jl), as these can then
automatically install their Python dependencies.  (To exploit this in
your own packages, use the `pyimport_conda` function described below.)

### Specifying the Python version

If you want to use a different version of Python than the default, you
can change the Python version by setting the `PYTHON` environment variable
to the path of the `python` (or `python3` etc.) executable and then re-running `Pkg.build("PyCall")`.
In Julia:

    ENV["PYTHON"] = "... path of the python executable ..."
    # ENV["PYTHON"] = raw"C:\Python37-x64\python.exe" # example for Windows, "raw" to not have to escape: "C:\\Python37-x64\\python.exe"

    # ENV["PYTHON"] = "/usr/bin/python3.7"           # example for *nix
    Pkg.build("PyCall")

Note also that you will need to re-run `Pkg.build("PyCall")` if your
`python` program changes significantly (e.g. you switch to a new
Python distro, or you switch from Python 2 to Python 3).

To force Julia to use its own Python distribution, via Conda, simply
set `ENV["PYTHON"]` to the empty string `""` and re-run `Pkg.build("PyCall")`.

The current Python version being used is stored in the `pyversion`
global variable of the `PyCall` module.  You can also look at
`PyCall.libpython` to find the name of the Python library or
`PyCall.pyprogramname` for the `python` program name.  If it is
using the Conda Python, `PyCall.conda` will be `true`.

(Technically, PyCall does not use the `python` program per se: it links
directly to the `libpython` library.  But it finds the location of
`libpython` by running `python` during `Pkg.build`.)

Subsequent builds of PyCall (e.g. when you update the package via
`Pkg.update`) will use the same Python executable name by default,
unless you set the `PYTHON` environment variable or delete the file
`Pkg.dir("PyCall","deps","PYTHON")`.

**Note:** If you use Python
[virtualenvs](https://docs.python-guide.org/en/latest/dev/virtualenvs/),
then be aware that PyCall *uses the virtualenv it was built with* by
default, even if you switch virtualenvs.  If you want to switch PyCall
to use a different virtualenv, then you should switch virtualenvs and
run `rm(Pkg.dir("PyCall","deps","PYTHON")); Pkg.build("PyCall")`.
Alternatively, see [Python virtual environments](#python-virtual-environments)
section below for switching virtual environment at run-time.

**Note:** Usually, the necessary libraries are installed along with
Python, but [pyenv on MacOS](https://github.com/JuliaPy/PyCall.jl/issues/122)
requires you to install it with `env PYTHON_CONFIGURE_OPTS="--enable-framework"
pyenv install 3.4.3`.  The Enthought Canopy Python distribution is
currently [not supported](https://github.com/JuliaPy/PyCall.jl/issues/42).
As a general rule, we tend to recommend the [Anaconda Python
distribution](https://store.continuum.io/cshop/anaconda/) on MacOS and
Windows, or using the Julia Conda package, in order to minimize headaches.

## Usage

Here is a simple example to call Python's `math.sin` function:

    using PyCall
    math = pyimport("math")
    math.sin(math.pi / 4) # returns ≈ 1/√2 = 0.70710678...

Type conversions are automatically performed for numeric, boolean,
string, IO stream, date/period, and function types, along with tuples,
arrays/lists, and dictionaries of these types. (Python functions can
be converted/passed to Julia functions and vice versa!)  Other types
are supported via the generic PyObject type, below.

Multidimensional arrays exploit the NumPy array interface for
conversions between Python and Julia.  By default, they are passed
from Julia to Python without making a copy, but from Python to Julia a
copy is made; no-copy conversion of Python to Julia arrays can be achieved
with the `PyArray` type below.

Keyword arguments can also be passed. For example, matplotlib's
[pyplot](https://matplotlib.org/) uses keyword arguments to specify plot
options, and this functionality is accessed from Julia by:

    plt = pyimport("matplotlib.pyplot")
    x = range(0;stop=2*pi,length=1000); y = sin.(3*x + 4*cos.(2*x));
    plt.plot(x, y, color="red", linewidth=2.0, linestyle="--")
    plt.show()

However, for better integration with Julia graphics backends and to
avoid the need for the `show` function, we recommend using matplotlib
via the Julia [PyPlot module](https://github.com/JuliaPy/PyPlot.jl).

Arbitrary Julia functions can be passed to Python routines taking
function arguments.  For example, to find the root of cos(x) - x,
we could call the Newton solver in scipy.optimize via:

    so = pyimport("scipy.optimize")
    so.newton(x -> cos(x) - x, 1)

A macro exists for mimicking Python's "with statement". For example:

    @pywith pybuiltin("open")("file.txt","w") as f begin
        f.write("hello")
    end

The type of `f` can be specified with `f::T` (for example, to override automatic
conversion, use `f::PyObject`). Similarly, if the context manager returns a type
which is automatically converted to a Julia type, you will have override this
via `@pywith EXPR::PyObject ...`.

If you are already familiar with Python, it perhaps is easier to use
`py"..."` and `py"""..."""` which are equivalent to Python's
[`eval`](https://docs.python.org/3/library/functions.html#eval) and
[`exec`](https://docs.python.org/3/library/functions.html#exec),
respectively:

```julia
py"""
import numpy as np

def sinpi(x):
    return np.sin(np.pi * x)
"""
py"sinpi"(1)
```

When creating a Julia module, it is a useful pattern to define Python
functions or classes in Julia's `__init__` and then use it in Julia
function with `py"..."`.

```julia
module MyModule

using PyCall

function __init__()
    py"""
    import numpy as np

    def one(x):
        return np.sin(x) ** 2 + np.cos(x) ** 2
    """
end

two(x) = py"one"(x) + py"one"(x)

end
```

Note that Python code in `py"..."` of above example is evaluated in a
Python namespace dedicated to `MyModule`.  Thus, Python function `one`
cannot be accessed outside `MyModule`.


## Troubleshooting

Here are solutions to some common problems:

* By default, PyCall [doesn't include the current directory in the Python search path](https://github.com/JuliaPy/PyCall.jl/issues/48).   If you want to do that (in order to load a Python module from the current directory), just run `pushfirst!(PyVector(pyimport("sys")."path"), "")`.

## Python object interfaces

PyCall provides many routines for
manipulating Python objects in Julia via a type `PyObject` described
below.  These can be used to have greater control over the types and
data passed between Julia and Python, as well as to access additional
Python functionality (especially in conjunction with the low-level interfaces
described later).

### Types

#### PyObject

The PyCall module also provides a new type `PyObject` (a wrapper around
`PyObject*` in Python's C API) representing a reference to a Python object.

Constructors `PyObject(o)` are provided for a number of Julia types,
and PyCall also supplies `convert(T, o::PyObject)` to convert
PyObjects back into Julia types `T`.  Currently, the types supported
are numbers (integer, real, and complex), booleans, strings, IO streams,
dates/periods, and functions, along with tuples and arrays/lists
thereof, but more are planned.  (Julia symbols are converted to Python
strings.)

Given `o::PyObject`, `o.attribute` in Julia is equivalent to `o.attribute`
in Python, with automatic type conversion.  To get an attribute as a
`PyObject` without type conversion, do `o."attribute"` instead.
The `keys(o::PyObject)` function returns an array of the available
attribute symbols.

Given `o::PyObject`, `get(o, key)` is equivalent to `o[key]` in
Python, with automatic type conversion.  To get as a `PyObject`
without type conversion, do `get(o, PyObject, key)`, or more generally
`get(o, SomeType, key)`.  You can also supply a default value to use
if the key is not found by `get(o, key, default)` or `get(o, SomeType,
key, default)`.  Similarly, `set!(o, key, val)` is equivalent to
`o[key] = val` in Python, and `delete!(o, key)` is equivalent to `del
o[key]` in Python.   For one or more *integer* indices, `o[i]` in Julia
is equivalent to `o[i-1]` in Python.

You can call an `o::PyObject` via `o(args...)` just like in Python
(assuming that the object is callable in Python).  The explicit
`pycall` form is still useful in Julia if you want to specify the
return type.

`pystr(o)` and `pyrepr(o)` are analogous to `str` and `repr` in Python, respectively.

#### Arrays and PyArray

##### From Julia to Python

Assuming you have NumPy installed (true by default if you use Conda),
then a Julia `a::Array` of NumPy-compatible elements is converted
by `PyObject(a)` into a NumPy wrapper for the *same data*, i.e. without
copying the data.  Julia arrays are stored in [column-major order](https://en.wikipedia.org/wiki/Row-major_order),
and since NumPy supports column-major arrays this is not a problem.

However, the *default* ordering of NumPy arrays created in *Python* is row-major, and some Python packages will throw an error if you try to pass them column-major NumPy arrays.  To deal with this, you can use `PyReverseDims(a)` to pass a Julia array as a row-major NumPy array with the dimensions *reversed*. For example, if `a` is a 3x4x5 Julia array, then `PyReverseDims(a)` passes it as a 5x4x3 NumPy row-major array (without making a copy of the underlying data).

A `Vector{UInt8}` object in Julia, by default, is converted to a Python
`bytearray` object.   If you want a `bytes` object instead, you can use
the function `pybytes(a)`.

##### From Python to Julia

Multidimensional NumPy arrays (`ndarray`) are supported and can be
converted to the native Julia `Array` type, which makes a copy of the data.

Alternatively, the PyCall module also provides a new type `PyArray` (a
subclass of `AbstractArray`) which implements a no-copy wrapper around
a NumPy array (currently of numeric types or objects only).  Just use
`PyArray` as the return type of a `pycall` returning an `ndarray`, or
call `PyArray(o::PyObject)` on an `ndarray` object `o`.  (Technically,
a `PyArray` works for any Python object that uses the NumPy array
interface to provide a data pointer and shape information.)

Conversely, when passing arrays *to* Python, Julia `Array` types are
converted to `PyObject` types *without* making a copy via NumPy,
e.g. when passed as `pycall` arguments.

#### PyVector

The PyCall module provides a new type `PyVector` (a subclass of
`AbstractVector`) which implements a no-copy wrapper around an
arbitrary Python list or sequence object.  (Unlike `PyArray`, the
`PyVector` type is not limited to `NumPy` arrays, although using
`PyArray` for the latter is generally more efficient.)  Just use
`PyVector` as the return type of a `pycall` returning a list or
sequence object (including tuples), or call `PyVector(o::PyObject)` on
a sequence object `o`.

A `v::PyVector` supports the usual `v[index]` referencing and assignment,
along with `delete!` and `pop!` operations.  `copy(v)` converts `v` to
an ordinary Julia `Vector`.

#### PyDict

Similar to `PyVector`, PyCall also provides a type `PyDict` (a subclass
of `Association`) that implements a no-copy wrapper around a Python
dictionary (or any object implementing the mapping protocol).  Just
use `PyDict` as the return type of a `pycall` returning a dictionary,
or call `PyDict(o::PyObject)` on a dictionary object `o`.  By
default, a `PyDict` is an `Any => Any` dictionary (or actually `PyAny
=> PyAny`) that performs runtime type inference, but if your Python
dictionary has known, fixed types you can instead use `PyDict{K,V}` given
the key and value types `K` and `V` respectively.

Currently, passing Julia dictionaries to Python makes a copy of the Julia
dictionary.

#### PyTextIO

Julia `IO` streams are converted into Python objects implementing the
[RawIOBase](https://docs.python.org/3/library/io.html#io.RawIOBase)
interface, so they can be used for binary I/O in Python.  However,
some Python code (notably unpickling) expects a stream implementing
the
[TextIOBase](https://docs.python.org/3/library/io.html#io.TextIOBase)
interface, which differs from RawIOBase mainly in that `read` an
`readall` functions return strings rather than byte arrays.  If you
need to pass an `IO` stream as a text-IO object, just call
`PyTextIO(io::IO)` to convert it.

(There doesn't seem to be any good way to determine automatically
whether Python wants a stream argument to return strings or binary
data.  Also, unlike Python, Julia does not open files separately in
"text" or "binary" modes, so we cannot determine the conversion simply
from how the file was opened.)

#### PyAny

The `PyAny` type is used in conversions to tell PyCall to detect the
Python type at runtime and convert to the corresponding native Julia
type.  That is, `pycall(func, PyAny, ...)` and `convert(PyAny,
o::PyObject)` both automatically convert their result to a native
Julia type (if possible).   This is convenient, but will lead
to slightly worse performance (due to the overhead of runtime type-checking
and the fact that the Julia JIT compiler can no longer infer the type).

### Calling Python

In most cases, PyCall automatically makes the
appropriate type conversions to Julia types based on runtime
inspection of the Python objects.  However greater control over these
type conversions (e.g. to use a no-copy `PyArray` for a Python
multidimensional array rather than copying to an `Array`) can be
achieved by using the lower-level functions below.  Using `pycall` in
cases where the Python return type is known can also improve
performance, both by eliminating the overhead of runtime type inference
and also by providing more type information to the Julia compiler.

* `pycall(function::PyObject, returntype::Type, args...)`.   Call the given
  Python `function` (typically looked up from a module) with the given
  `args...` (of standard Julia types which are converted automatically to
  the corresponding Python types if possible), converting the return value
  to `returntype` (use a `returntype` of `PyObject` to return the unconverted
  Python object reference, or of `PyAny` to request an automated conversion).
  For convenience, a macro `@pycall` exists which automatically converts
  `@pycall function(args...)::returntype` into
  `pycall(function,returntype,args...)`.

* `py"..."` evaluates `"..."` as Python code, equivalent to
  Python's [`eval`](https://docs.python.org/3/library/functions.html#eval) function, and returns the result
  converted to `PyAny`.  Alternatively, `py"..."o` returns the raw `PyObject`
  (which can then be manually converted if desired).   You can interpolate
  Julia variables and other expressions into the Python code with `$`,
  which interpolates the *value* (converted to `PyObject`) of the given
  expression---data is not passed as a string, so this is different from
  ordinary Julia string interpolation.  e.g. `py"sum($([1,2,3]))"` calls the
  Python `sum` function on the Julia array `[1,2,3]`, returning `6`.
  In contrast, if you use `$$` before the interpolated expression, then
  the value of the expression is inserted as a string into the Python code,
  allowing you to generate Python code itself via Julia expressions.
  For example, if `x="1+1"` in Julia, then `py"$x"` returns the string `"1+1"`,
  but `py"$$x"` returns `2`.
  If you use `py"""..."""` to pass a *multi-line* string, the string can
  contain arbitrary Python code (not just a single expression) to be evaluated,
  but the return value is `nothing`; this is useful e.g. to define pure-Python
  functions, and is equivalent to Python's
  [`exec`](https://docs.python.org/3/library/functions.html#exec) function.
  (If you define a Python global `g` in a multiline `py"""..."""`
  string, you can retrieve it in Julia by subsequently evaluating `py"g"`.)

  When `py"..."` is used inside a Julia module, it uses a Python namespace
  dedicated to this Julia module.  Thus, you can define Python function
  using `py"""...."""` in your module without worrying about name clash
  with other Python code.  Note that Python functions _must_ be defined in
  `__init__`.  Side-effect in Python occurred at top-level Julia scope
  cannot be used at run-time for precompiled modules.

* `pybuiltin(s)`: Look up `s` (a string or symbol) among the global Python
  builtins.  If `s` is a string it returns a `PyObject`, while if `s` is a
  symbol it returns the builtin converted to `PyAny`.  (You can also use `py"s"`
  to look up builtins or other Python globas.)

Occasionally, you may need to pass a keyword argument to Python that
is a [reserved word](https://en.wikipedia.org/wiki/Reserved_word) in Julia.
For example, calling `f(x, function=g)` will fail because `function` is
a reserved word in Julia. In such cases, you can use the lower-level
Julia syntax `f(x; :function=>g)`.

### Calling Julia from Python

Julia functions get converted to callable Python objects, so you
can easily call Julia from Python via callback function arguments.
The [pyjulia module](https://github.com/JuliaPy/pyjulia) allows you
to call Julia directly from Python, and also uses PyCall to do its
conversions.

A Julia function `f(args...)` is ordinarily converted to a callable
Python object `p(args...)` that first converts its Python arguments
into Julia arguments by the default `PyAny` conversion, calls `f`,
then converts the Julia return value of `f` back into a Python object
with the default `PyObject(...)` conversion.    However, you can
exert lower-level control over these argument/return conversions
by calling `pyfunction(f, ...)` or `pyfunctionret(f, ...)`; see the
documentation `?pyfunction` and `?pyfunctionret` for more information.

### Defining Python Classes

`@pydef` creates a Python class whose methods are implemented in Julia.
For instance,

    P = pyimport("numpy.polynomial")
    @pydef mutable struct Doubler <: P.Polynomial
        function __init__(self, x=10)
            self.x = x
        end
        my_method(self, arg1::Number) = arg1 + 20
        x2.get(self) = self.x * 2
        function x2.set!(self, new_val)
            self.x = new_val / 2
        end
    end
    Doubler().x2

is essentially equivalent to the following Python code:

    import numpy.polynomial
    class Doubler(numpy.polynomial.Polynomial):
        def __init__(self, x=10):
            self.x = x
        def my_method(self, arg1): return arg1 + 20
        @property
        def x2(self): return self.x * 2
        @x2.setter
        def x2(self, new_val):
            self.x = new_val / 2
    Doubler().x2

The method arguments and return values are automatically converted between Julia and Python. All Python special methods are supported (`__len__`, `__add__`, etc.).

`@pydef` allows for multiple inheritance of Python classes:

    @pydef mutable struct SomeType <: (BaseClass1, BaseClass2)
        ...
    end

Here's another example using [Tkinter](https://wiki.python.org/moin/TkInter):

    using PyCall
    tk = pyimport("Tkinter")

    @pydef mutable struct SampleApp <: tk.Tk
        __init__(self, args...; kwargs...) = begin
            tk.Tk.__init__(self, args...; kwargs...)
            self.label = tk.Label(text="Hello, world!")
            self.label.pack(padx=10, pady=10)
        end
    end

    app = SampleApp()
    app.mainloop()

Class variables are also supported:

    using PyCall
    @pydef mutable struct ObjectCounter
        obj_count = 0 # Class variable
        function __init__(::PyObject)
            ObjectCounter.obj_count += 1
        end
    end

### GUI Event Loops

For Python packages that have a graphical user interface (GUI),
notably plotting packages like matplotlib (or MayaVi or Chaco), it is
convenient to start the GUI event loop (which processes things like
mouse clicks) as an asynchronous task within Julia, so that the GUI is
responsive without blocking Julia's input prompt.  PyCall includes
functions to implement these event loops for some of the most common
cross-platform [GUI
toolkits](https://en.wikipedia.org/wiki/Widget_toolkit):
[wxWidgets](http://www.wxwidgets.org/), [GTK+](http://www.gtk.org/)
version 2 (via [PyGTK](http://www.pygtk.org/)) or version 3 (via
[PyGObject](https://pygobject.readthedocs.io/en/latest/)), and
[Qt](http://qt-project.org/) (via the [PyQt4](https://wiki.python.org/moin/PyQt4)
or [PySide](http://qt-project.org/wiki/PySide) Python modules).

You can set a GUI event loop via:

* `pygui_start(gui::Symbol=pygui())`.  Here, `gui` is either `:wx`,
  `:gtk`, `:gtk3`, `:tk`, or `:qt` to start the respective toolkit's
  event loop.  (`:qt` will use PyQt4 or PySide, preferring the former;
  if you need to require one or the other you can instead use
  `:qt_pyqt4` or `:qt_pyside`, respectively.) It defaults to the
  return value of `pygui()`, which returns a current default GUI (see
  below).  Passing a `gui` argument also changes the default GUI,
  equivalent to calling `pygui(gui)` below.  You may start event loops
  for more than one GUI toolkit (to run simultaneously).  Calling
  `pygui_start` more than once for a given toolkit does nothing
  (except to change the current `pygui` default).

* `pygui()`: return the current default GUI toolkit (`Symbol`).  If
  the default GUI has not been set already, this is the first of
  `:tk`, `:qt`, `:wx`, `:gtk`, or `:gtk3` for which the corresponding
  Python package is installed.  `pygui(gui::Symbol)` changes the
  default GUI to `gui`.

* `pygui_stop(gui::Symbol=pygui())`: Stop any running event loop for `gui`
  (which defaults to the current return value of `pygui`).  Returns
  `true` if an event loop was running, and `false` otherwise.

To use these GUI facilities with some Python libraries, it is enough
to simply start the appropriate toolkit's event-loop before importing
the library.  However, in other cases it is necessary to explicitly
tell the library which GUI toolkit to use and that an interactive mode
is desired.  To make this even easier, it is convenient to have
wrapper modules around popular Python libraries, such as the [PyPlot
module](https://github.com/JuliaPy/PyPlot.jl) for Julia.

### Low-level Python API access

If you want to call low-level functions in the Python C API, you can
do so using `ccall`.

* Use `@pysym(func::Symbol)` to get a function pointer to pass to `ccall`
  given a symbol `func` in the Python API.  e.g. you can call
  `int Py_IsInitialized()` by `ccall(@pysym(:Py_IsInitialized), Int32, ())`.

* PyCall defines the typealias `PyPtr` for `PythonObject*` argument types,
  and `PythonObject` (see above) arguments are correctly converted to this
  type.  `PythonObject(p::PyPtr)` creates a Julia wrapper around a
  `PyPtr` return value.

* Use `PyObject` and the `convert` routines mentioned above to convert
  Julia types to/from `PyObject*` references.

* If a new reference is returned by a Python function, immediately
  convert the `PyPtr` return values to `PythonObject` objects in order to
  have their Python reference counts decremented when the object is
  garbage collected in Julia.  i.e. `PythonObject(ccall(func, PyPtr, ...))`.
  **Important**: for Python routines that return a borrowed reference,
  you should instead do `pyincref(PyObject(...))` to obtain a new
  reference.

* You can call `pyincref(o::PyObject)` and `pydecref(o::PyObject)` to
  manually increment/decrement the reference count.  This is sometimes
  needed when low-level functions steal a reference or return a borrowed one.

* The function `pyerr_check(msg::AbstractString)` can be used to check if a
  Python exception was thrown, and throw a Julia exception (which includes
  both `msg` and the Python exception object) if so.  The Python
  exception status may be cleared by calling `pyerr_clear()`.

* The function `pytype_query(o::PyObject)` returns a native Julia
  type that `o` can be converted into, if possible, or `PyObject` if not.

* `pyisinstance(o::PyObject, t::Symbol)` can be used to query whether
  `o` is of a given Python type (where `t` is the identifier of a global
  `PyTypeObject` in the Python C API), e.g. `pyisinstance(o, :PyDict_Type)`
  checks whether `o` is a Python dictionary.  Alternatively,
  `pyisinstance(o::PyObject, t::PyObject)` performs the same check
  given a Python type object `t`.  `pytypeof(o::PyObject)` returns the
  Python type of `o`, equivalent to `type(o)` in Python.

### Using PyCall from Julia Modules

You can use PyCall from any Julia code, including within Julia modules. However, some care is required when using PyCall from [precompiled Julia modules](https://docs.julialang.org/en/latest/manual/modules/#module-initialization-and-precompilation). The key thing to remember is that *all Python objects* (any `PyObject`) contain *pointers* to memory allocated by the Python runtime, and such pointers *cannot be saved* in precompiled constants.   (When a precompiled library is reloaded, these pointers will not contain valid memory addresses.)

The solution is fairly simple:

* Python objects that you create in functions called *after* the module is loaded are always safe.

* If you want to store a Python object in a global variable that is initialized automatically when the module is loaded, then initialize the variable in your module's `__init__` function.  For a type-stable global constant, initialize the constant to `PyNULL()` at the top level, and then use the `copy!` function in your module's `__init__` function to mutate it to its actual value.

For example, suppose your module uses the `scipy.optimize` module, and you want to load this module when your module is loaded and store it in a global constant `scipy_opt`.  You could do:

```jl
__precompile__() # this module is safe to precompile
module MyModule
using PyCall

const scipy_opt = PyNULL()

function __init__()
    copy!(scipy_opt, pyimport_conda("scipy.optimize", "scipy"))
end

end
```
Then you can access the `scipy.optimize` functions as `scipy_opt.newton`
and so on.

Here, instead of `pyimport`, we have used the function `pyimport_conda`.   The second argument is the name of the [Anaconda package](https://docs.continuum.io/anaconda/pkg-docs) that provides this module.   This way, if importing `scipy.optimize` fails because the user hasn't installed `scipy`, it will either (a) automatically install `scipy` and retry the `pyimport` if PyCall is configured to use the [Conda](https://github.com/Luthaf/Conda.jl) Python install (or
any other Anaconda-based Python distro for which the user has installation privileges), or (b) throw an error explaining that `scipy` needs to be installed, and explain how to configure PyCall to use Conda so that it can be installed automatically.   More generally, you can call `pyimport_conda(module, package, channel)` to specify an optional Anaconda "channel" for installing non-standard Anaconda packages.

## Python virtual environments

Python virtual environments created by [`venv`](https://docs.python.org/3/library/venv.html) and [`virtualenv`](https://virtualenv.pypa.io/en/latest/)
can be used from `PyCall`, *provided that the Python executable used
in the virtual environment is linked against the same `libpython` used
by `PyCall`*.  Note that virtual environments created by `conda` are not
supported.

To use `PyCall` with a certain virtual environment, set the environment
variable `PYCALL_JL_RUNTIME_PYTHON` *before* importing `PyCall` to
path to the Python executable.  For example:

```julia
$ source PATH/TO/bin/activate  # activate virtual environment in system shell

$ julia  # start Julia
...

julia> ENV["PYCALL_JL_RUNTIME_PYTHON"] = Sys.which("python")
"PATH/TO/bin/python3"

julia> using PyCall

julia> pyimport("sys").executable
"PATH/TO/bin/python3"
```
Similarly, the `PYTHONHOME` path can be changed by the environment variable
`PYCALL_JL_RUNTIME_PYTHONHOME`.

## Author

This package was written by [Steven G. Johnson](https://math.mit.edu/~stevenj/).
