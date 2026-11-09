module PyBridge

using PythonCall

export as_numpy, from_numpy, moving_average_np, moving_average, boundary_bytes

# A Python object cannot be created while the module is precompiled: make an
# empty handle now and fill it when the module is loaded (PythonCall's pattern).
const np = PythonCall.pynew()
__init__() = PythonCall.pycopy!(np, pyimport("numpy"))

"""
    as_numpy(v::Vector{Float64}) -> Py

A NumPy array over the same memory as `v` (no copy): a write through either
side is visible on the other.
"""
as_numpy(v::Vector{Float64}) = np.asarray(v)

"""
    as_numpy(A::Matrix{Float64}) -> Py

A NumPy view of `A` with `A[i, j] == a[i-1, j-1]`. Julia stores columns
contiguously, so the view is in Fortran (column-major) order.
"""
as_numpy(A::Matrix{Float64}) = np.asarray(A)

"""
    from_numpy(a::Py) -> Array{Float64}

A Julia copy of a 1-D or 2-D NumPy array, with the same indices (shifted by
one) whatever the array's memory order, and integer arrays converted.
"""
function from_numpy(a::Py)
    nd = pyconvert(Int, a.ndim)
    nd == 1 && return pyconvert(Vector{Float64}, a)
    nd == 2 && return pyconvert(Matrix{Float64}, a)
    throw(ArgumentError("from_numpy takes a 1-D or 2-D array, got $nd dimensions"))
end

check_window(n, k) = 1 <= k <= n || throw(ArgumentError("window k = $k must be in 1:$n"))

"""
    moving_average_np(v, k) -> Vector{Float64}

Means of the n - k + 1 full windows of length `k`, computed by `numpy.convolve`.
"""
function moving_average_np(v::AbstractVector{<:Real}, k::Integer)
    check_window(length(v), k)
    w = np.ones(k) / k
    return pyconvert(Vector{Float64}, np.convolve(np.asarray(Vector{Float64}(v)), w; mode = "valid"))
end

"""
    moving_average(v, k) -> Vector{Float64}

The same means in Julia with a running sum: one addition and one subtraction
per window, and no allocation besides the result.
"""
function moving_average(v::AbstractVector{<:Real}, k::Integer)
    n = length(v)
    check_window(n, k)
    out = Vector{Float64}(undef, n - k + 1)
    s = 0.0
    for i in 1:k
        s += v[i]
    end
    out[1] = s / k
    for i in 2:n-k+1
        s += v[i+k-1] - v[i-1]
        out[i] = s / k
    end
    return out
end

"""
    boundary_bytes(n) -> (view = bytes, copy = bytes)

Bytes allocated by `as_numpy` (a view) and by `from_numpy` (a copy) on a vector
of length `n`, each measured on its second call (the first one compiles).
"""
function boundary_bytes(n::Integer)
    v = collect(1.0:n)                         # values do not matter, only the size
    a = as_numpy(v)
    as_numpy(v); from_numpy(a)                 # warm-up: compile both calls first
    view = @allocated as_numpy(v)
    copy = @allocated from_numpy(a)
    return (view = view, copy = copy)
end

end # module
