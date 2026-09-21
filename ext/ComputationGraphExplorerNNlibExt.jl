# Copyright (c) 2026 Benoît Legat
# SPDX-License-Identifier: MIT

module ComputationGraphExplorerNNlibExt

import ComputationGraphExplorer as CGE
import NNlib

function NNlib.batched_mul(x::N, y::N) where {N<:CGE.Node}
    return N(:batched_mul, N[x, y], NNlib.batched_mul(x.value, y.value))
end

function NNlib.batched_mul(x::N, y) where {N<:CGE.Node}
    return NNlib.batched_mul(x, N(y))
end

function NNlib.batched_mul(x, y::N) where {N<:CGE.Node}
    return NNlib.batched_mul(N(x), y)
end

function NNlib.batched_transpose(x::N) where {N<:CGE.Node}
    return N(:batched_transpose, N[x], NNlib.batched_transpose(x.value))
end

end
