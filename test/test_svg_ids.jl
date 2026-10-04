# Copyright (c) 2026 Benoît Legat
# SPDX-License-Identifier: MIT

import ComputationGraphExplorer as CGE
import Test

Test.@testset "Independent SVG namespaces" begin
    ids(svg) = [m[1] for m in eachmatch(r"\bid=[\"']([^\"']+)[\"']", svg)]
    references(svg) =
        [m[1] for m in eachmatch(r"(?:\bhref=[\"']#|url\(\s*[\"']?#)([^\"'\s)]+)", svg)]

    # Cover Cairo's glyph, clip and paint references, without changing colors
    # or references to external resources. SVG 2 also permits plain href.
    source = """
    <svg><defs>
      <g id="glyph-0-1"/><clipPath id='clip1'/><linearGradient id="paint1"/>
    </defs>
    <use xlink:href="#glyph-0-1"/><use href='#glyph-0-1'/>
    <g clip-path="url(#clip1)" fill="url('#paint1')"/>
    <g style='clip-path: url( "#clip1" )' fill="#abcdef"/>
    <image href="external.svg#other"/>
    </svg>
    """
    scoped = CGE._namespace_svg(source)
    Test.@test length(ids(scoped)) == 3
    Test.@test length(references(scoped)) == 5
    Test.@test all(startswith("cge-"), ids(scoped))
    Test.@test issubset(references(scoped), ids(scoped))
    Test.@test occursin("fill=\"#abcdef\"", scoped)
    Test.@test occursin("href=\"external.svg#other\"", scoped)

    Node = CGE.Node{Float64,Float64}
    x, y = Node(0.2), Node(0.3)
    first_graph = CGE.Graph(x * y; names = IdDict(x => "x[1]", y => "y[1]"))
    second_graph = CGE.Graph(exp(x); names = IdDict(x => "other"))
    first_frame = CGE.capture_frame(first_graph, "x' * y")
    second_frame = CGE.capture_frame(second_graph, "Other graph")

    svgs = [
        CGE.render_svg(first_graph, first_frame; responsive = true),
        CGE.render_svg(second_graph, second_frame; responsive = true),
        CGE.render_svg(first_graph, first_frame; responsive = true),
        CGE.render_svg(first_graph, first_frame; responsive = false),
    ]
    Test.@test occursin("width=\"100%\"", svgs[1])
    Test.@test occursin("width=\"1100\" height=\"620\"", svgs[4])
    mktempdir() do directory
        for responsive in (true, false)
            path = joinpath(directory, "graph-$responsive.svg")
            Test.@test CGE.save_svg(path, first_graph, first_frame; responsive) == path
            push!(svgs, read(path, String))
        end
    end
    for svg in svgs
        Test.@test !isempty(ids(svg))
        Test.@test !isempty(references(svg))
        Test.@test issubset(references(svg), ids(svg))
    end
    # Check the IDs as they would appear when all six SVGs share one document.
    combined_ids = reduce(vcat, ids.(svgs))
    Test.@test allunique(combined_ids)
end
