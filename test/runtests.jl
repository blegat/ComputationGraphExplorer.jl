# Copyright (c) 2026 Benoît Legat
# SPDX-License-Identifier: MIT

using ComputationGraphExplorer
using LinearAlgebra
using Test

struct EmptyMetadata end
EmptyMetadata(::Any) = EmptyMetadata()

mutable struct DispatchMetadata
    seeded::Bool
    calls::Vector{Any}
end
DispatchMetadata(::Any) = DispatchMetadata(false, Any[])

const DispatchNode = ExprNode{Any,DispatchMetadata}

ComputationGraphExplorer.metadata_rows(data::DispatchMetadata) =
    ["seeded" => string(data.seeded)]

function ComputationGraphExplorer.seed_metadata!(data::DispatchMetadata, is_output::Bool)
    data.seeded = is_output
    empty!(data.calls)
    return data
end

function ComputationGraphExplorer.pullback!(op, output::DispatchNode, ::DispatchNode...)
    push!(output.metadata.calls, op)
    return output
end

function ComputationGraphExplorer.pullback!(
    ::typeof(Base.broadcasted),
    op,
    output::DispatchNode,
    ::DispatchNode...,
)
    push!(output.metadata.calls, (:broadcasted, op))
    return output
end

@testset "scalar expression graph" begin
    Node = ExprNode{Float64,EmptyMetadata}
    x, y = Node(2), Node(3)
    s1 = x * y
    output = s1 * (s1 + x)
    @test output.value == 48
    @test length(topological_order(output)) == 5
    text = sprint(show, output)
    @test startswith(text, "Computation graph with 5 nodes:")
    @test count("[2] *: value = 6.0", text) == 1
    @test occursin("↩ [2]", text)
    @test occursin("↩ [3]", text)
    @test !showable(MIME"image/svg+xml"(), output)

    visualization = visualize(output)
    @test sprint(show, visualization) == "Visualization of a computation graph with 5 nodes"
    @test showable(MIME"image/svg+xml"(), visualization)
    visualization_svg = repr(MIME"image/svg+xml"(), visualization)
    @test occursin("width=\"1100\" height=\"620\"", visualization_svg)
    @test !occursin("width=\"100%\"", visualization_svg)
    custom_svg = repr(
        MIME"image/svg+xml"(),
        visualize(output; width = 700, height = 400, responsive = true),
    )
    @test occursin("width=\"100%\"", custom_svg)
    @test occursin("viewBox=\"0 0 700 400\"", custom_svg)

    graph = ExprGraph(output; names = IdDict(x => "x", y => "y"))
    states = forward_frames(graph)
    @test length(states) == 6
    svg = render_svg(graph, states[end])
    @test occursin("<svg", svg)
    @test occursin("xmlns:xlink=\"http://www.w3.org/1999/xlink\"", svg)
    @test occursin("width=\"1100\" height=\"620\"", svg)
    @test occursin("width=\"100%\"", render_svg(graph, states[end]; responsive = true))
    @test ComputationGraphExplorer._fmt([1.0, 2.0]) == "[1, 2]"
    @test ComputationGraphExplorer._fmt([1.0 2.0; 3.0 4.0]) == "[1 2; 3 4]"

    # Graph construction is independent of reverse-mode metadata. If no rule
    # was provided for an operation, reverse dispatch reports its exact method.
    @test_throws MethodError ComputationGraphExplorer.pullback!(x + y)
end

@testset "operators and array interface" begin
    x, y = DispatchNode(4.0), DispatchNode(2.0)
    @test (x + y).value == 6
    @test (x + 2).value == 6
    @test (2 + x).value == 6
    @test (x - y).value == 2
    @test (x - 2).value == 2
    @test (6 - x).value == 2
    @test (-x).value == -4
    @test (x * y).value == 8
    @test (x * 2).value == 8
    @test (2 * x).value == 8
    @test (x / y).value == 2
    @test (x / 2).value == 2
    @test (8 / x).value == 2
    @test (x^y).value == 16
    @test (x^2).value == 16
    @test (2^y).value == 4
    @test (-x).op == :-
    @test tanh(x).value == tanh(4)
    @test exp(y).value == exp(2)
    @test log(x).value == log(4)
    @test sqrt(x).value == 2
    @test zero(x).value == 0
    @test copy(x) === x
    @test x > y
    @test x > 3
    @test 5 > x

    a = DispatchNode([1.0 2.0; 3.0 4.0])
    b = DispatchNode([2.0 3.0; 4.0 5.0])
    @test length(a) == 4
    @test size(a) == (2, 2)
    @test size(a, 1) == 2
    @test ndims(a) == 2
    @test eltype(a) == Float64
    @test sum(a).value == 10
    @test sum(a; dims = 1).value == [4.0 6.0]
    @test maximum(a).value == 4
    @test maximum(a; dims = (2,)).value == [2.0; 4.0;;]
    @test a'.value == a.value'
    @test a[[2], :].value == a.value[[2], :]
    @test reduce(hcat, [x, y]).value == [4.0 2.0]

    @test Base.materialize(Base.broadcasted(-, a)).value == -a.value
    @test Base.broadcasted(+, a, b).value == a.value .+ b.value
    @test Base.broadcasted(*, a, 2).value == a.value .* 2
    @test Base.broadcasted(/, 12, a).value == 12 ./ a.value
    @test Base.materialize(Base.broadcasted(Base.literal_pow, ^, a, Val(2))).value ==
          a.value .^ 2
    @test Base.broadcasted(min, a, 2).value == min.(a.value, 2)
    @test Base.broadcasted(max, 2, a).value == max.(2, a.value)

    @test metadata_rows(EmptyMetadata()) == Pair{String,String}[]
    @test occursin("seeded = false", sprint(show, x))
    large_matrix = fill(1.0, 5, 5)
    array3 = reshape(1:8, 2, 2, 2)
    @test ComputationGraphExplorer._fmt(large_matrix) == summary(large_matrix)
    @test ComputationGraphExplorer._fmt(array3) == summary(array3)
end

@testset "pullback dispatch" begin
    x, y = DispatchNode(4.0), DispatchNode(2.0)
    array = DispatchNode([1.0 2.0; 3.0 4.0])
    nodes = Any[
        DispatchNode(:+, DispatchNode[x], 4.0)=>+,
        x+y=>+,
        -x=>-,
        x-y=>-,
        DispatchNode(:*, DispatchNode[x], 4.0)=>*,
        x*y=>*,
        x/y=>/,
        x^y=>^,
        tanh(x)=>tanh,
        exp(x)=>exp,
        log(x)=>log,
        sqrt(x)=>sqrt,
        sum(array)=>sum,
        sum(array; dims = 1)=>sum,
        maximum(array)=>maximum,
        maximum(array; dims = 1)=>maximum,
        array'=>adjoint,
        reduce(hcat, [x, y])=>hcat,
        array[[1], :]=>getindex,
    ]
    for op in (+, -, *, /, ^, tanh, exp, log, sqrt, min, max)
        node =
            op in (tanh, exp, log, sqrt) ? Base.broadcasted(op, array) :
            Base.broadcasted(op, array, array)
        push!(nodes, node => (:broadcasted, op))
    end
    push!(
        nodes,
        DispatchNode(:custom_operation, DispatchNode[x], x.value) => Val(:custom_operation),
    )

    for (node, expected) in nodes
        pullback!(node)
        @test only(node.metadata.calls) == expected
    end

    output = x * y
    backward!(output)
    @test output.metadata.seeded
    @test !x.metadata.seeded
    @test !y.metadata.seeded
    @test only(output.metadata.calls) == *
    @test pullback!(x) === x
end

@testset "small array value union" begin
    Value = Union{Float64,Vector{Float64},Matrix{Float64},Adjoint{Float64,Matrix{Float64}}}
    Node = ExprNode{Value,EmptyMetadata}
    x = Node(reshape(collect(1.0:6.0), 2, 3))
    w = Node(reshape(collect(1.0:6.0), 3, 2))
    product = x * w
    @test product.value == x.value * w.value
    @test sum(product; dims = 2).value == sum(product.value; dims = 2)
    @test w'.value isa Adjoint{Float64,Matrix{Float64}}
    @test (x' * x).value == x.value' * x.value
end

@testset "rendering and exporters" begin
    x = DispatchNode([1.0, 2.0])
    y = DispatchNode([3.0, 4.0])
    output = reduce(hcat, [x, y])
    graph = ExprGraph(output; names = IdDict(x => "x", y => "y", output => "A"))
    frame = capture_frame(graph, "Array graph"; active = output)

    svg = render_svg(graph, frame; exam = true)
    @test occursin("viewBox=\"0 0 1100 260\"", svg)
    @test all(!isempty, values(frame.metadata))
    @test render_svg(graph, frame; responsive = false) isa String
    no_metadata = capture_frame(graph, "No metadata"; show_metadata = false)
    @test all(isempty, values(no_metadata.metadata))
    @test render_svg(graph, no_metadata) isa String

    mktempdir() do directory
        svg_path = joinpath(directory, "graph.svg")
        responsive_path = joinpath(directory, "responsive.svg")
        png_path = joinpath(directory, "graph.png")
        eps_path = joinpath(directory, "graph.eps")
        @test save_svg(svg_path, graph, frame) == svg_path
        @test save_svg(responsive_path, graph, frame; responsive = true) == responsive_path
        @test save_png(png_path, graph, frame; density = 72, width = 550) == png_path
        @test save_eps(eps_path, graph, frame) == eps_path
        @test all(isfile, (svg_path, responsive_path, png_path, eps_path))
        @test occursin("width=\"100%\"", read(responsive_path, String))
    end
end

include(joinpath(@__DIR__, "..", "examples", "scalar_reverse.jl"))
using .ScalarReverseExample

@testset "scalar reverse example" begin
    graph = ScalarReverseExample.example()
    order = topological_order(graph.output)
    ScalarReverseExample.backward!(graph.output, order)
    derivatives =
        Dict(graph.names[node] => node.metadata.derivative for node in keys(graph.names))
    @test derivatives["x"] == 48
    @test derivatives["y"] == 28
    @test derivatives["s₁"] == 14
    @test derivatives["s₂"] == 6

    # Compilation and topology discovery are deliberately outside the
    # measurement; repeated reverse sweeps over a recorded graph must allocate
    # no memory.
    ScalarReverseExample.backward!(graph.output, order)
    @test @allocated(ScalarReverseExample.backward!(graph.output, order)) == 0
end
