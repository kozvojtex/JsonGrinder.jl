module JsonGrinder
using Mill, JSON, Printf, Flux
using Mill: paddedprint, COLORS
include("schema.jl")
include("html_show_tools.jl")

using Mill: ArrayNode, BagNode, TreeNode, catobs
include("extractors/extractarray.jl")
include("extractors/extractbranch.jl")
include("extractors/extractcategorical.jl")
include("extractors/extractscalar.jl")
include("extractors/extractstring.jl")
include("extractors/extractvector.jl")
include("extractors/extractonehot.jl")
include("extractors/multirepresentation.jl")

export ExtractScalar, ExtractCategorical, ExtractArray, ExtractBranch, ExtractOneHot, ExtractVector, MultipleRepresentation, ExtractString
export suggestextractor, schema, extractbatch, generate_html

include("hierarchical_utils.jl")

# Base.show(io::IO, ::T) where T <: Union{AbstractNode, MillModel, AggregationFunction} = show(io, Base.typename(T))
# Base.show(io::IO, ::MIME"text/plain", n::Union{AbstractNode, MillModel}) = HierarchicalUtils.printtree(io, n; trunc_level=2, trav=false)
Base.getindex(n::Union{JSONEntry, AbstractExtractor}, i::AbstractString) = HierarchicalUtils.walk(n, i)

end # module
