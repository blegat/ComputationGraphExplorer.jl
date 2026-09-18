# Copyright (c) 2026 Benoît Legat
# SPDX-License-Identifier: MIT

module ScalarReverseExample

import ComputationGraphExplorer as CGE

export ScalarReverseData, ScalarNode, example, frames

mutable struct ScalarReverseData
    derivative::Float64
end
CGE.metadata(::Type{ScalarReverseData}, ::Float64) = ScalarReverseData(0.0)

function CGE.metadata_rows(data::ScalarReverseData)
    value = iszero(data.derivative) ? "0" : string(data.derivative)
    return ["adjoint" => value]
end

const ScalarNode = CGE.Node{Float64,ScalarReverseData}

function CGE.seed_metadata!(data::ScalarReverseData, is_output::Bool)
    data.derivative = is_output ? 1.0 : 0.0
end

function example(; x = 2.0, y = 3.0)
    xnode = ScalarNode(x)
    ynode = ScalarNode(y)
    s1 = xnode * ynode
    s2 = s1 + xnode
    output = s1 * s2
    names = IdDict(xnode => "x", ynode => "y", s1 => "s₁", s2 => "s₂", output => "f")
    return CGE.Graph(output; names)
end

function CGE.pullback!(::typeof(+), node::ScalarNode, args::ScalarNode...)
    for arg in args
        arg.metadata.derivative += node.metadata.derivative
    end
end

function CGE.pullback!(::typeof(*), node::ScalarNode, x::ScalarNode, y::ScalarNode)
    x.metadata.derivative += node.metadata.derivative * y.value
    y.metadata.derivative += node.metadata.derivative * x.value
end

function frames(graph::CGE.Graph)
    result = CGE.forward_frames(graph)
    order = CGE.topological_order(graph.output)
    for node in order
        node.metadata.derivative = 0.0
    end
    graph.output.metadata.derivative = 1.0
    push!(
        result,
        CGE.capture_frame(graph, "Reverse pass: seed f̄ = 1"; active = graph.output),
    )
    for node in reverse(order)
        isempty(node.args) && continue
        CGE.pullback!(node)
        push!(
            result,
            CGE.capture_frame(
                graph,
                "Reverse pass: propagate from $(graph.names[node])";
                active = node,
            ),
        )
    end
    return result
end

end
