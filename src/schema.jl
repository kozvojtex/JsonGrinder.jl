using JSON, Printf
import Base: merge, length
import Mill: reflectinmodel

abstract type AbstractExtractor end
abstract type JSONEntry end
StringOrNumber = Union{String,Number}
max_keys = 10000

# so I can pretty print symbols
length(s::Symbol) = length(string(s))

function updatemaxkeys!(n::Int)
	global max_keys = n
end

"""
	mutable struct Entry <: JSONEntry
		counts::Dict{Any,Int}
		updated::Int
	end

	Keeps statistics about scalar values of a one key and also about items inside a key
	`count` counts how many times given value appeared (at most max_keys is held)
	`updated` counts how many times the entry was updated
"""
mutable struct Entry <: JSONEntry
	counts::Dict{Any,Int}
	updated::Int
end

Entry() = Entry(Dict{Any,Int}(),0);
types(e::Entry) = unique(typeof.(collect(keys(e.counts))))
Base.keys(e::Entry) = sort(collect(keys(e.counts)))
function Base.show(io::IO, e::Entry;pad =[], key = "")
	key *= isempty(key) ? ""  : ": "
	paddedprint(io, @sprintf("%s[Scalar - %s], %d unique values, updated = %d\n",key,join(types(e)),length(keys(e.counts)),e.updated))
end

function suggestextractor(e::Entry, settings = NamedTuple())
	t = promote_type(unique(typeof.(keys(e.counts)))...)
	t == Any  && @error "JSON does not have a fixed type scheme, quitting"

	for (c, ex) in get(settings, :scalar_extractors, default_scalar_extractor())
		c(e) && return ex(e)
	end
end

function default_scalar_extractor()
	[(e -> (length(keys(e.counts)) / e.updated < 0.1  && length(keys(e.counts)) <= 10000),
		e -> ExtractCategorical(collect(keys(e.counts)))),
	(e -> true,
		e -> extractscalar(promote_type(unique(typeof.(keys(e.counts)))...))),]
end


"""
		function update!(a::Entry,v)

		updates the entry when seeing value v
"""
function update!(a::Entry,v)
	if length(keys(a.counts)) < max_keys
		a.counts[v] = get(a.counts,v,0) + 1
	end
	a.updated +=1
end


function merge(es::Entry...)
	updates_merged = sum(map(x->x.updated, es))
	counts_merged = merge(+, map(x->x.counts, es)...)
	Entry(counts_merged, updates_merged)
end


"""
		mutable struct ArrayEntry <: JSONEntry
			items
			l::Dict{Int,Int}
			updated::Int
		end

		keeps statistics about an array entry in JSON.
		`items` is typeof `Entry` or nothing and keeps statistics about the elements of the array
		`l` keeps histogram of message length
		`updated` counts how many times the struct was updated.
"""
mutable struct ArrayEntry <: JSONEntry
	items	# Tried to make type stable optional type, didn't work
	l::Dict{Int,Int}
	updated::Int
end

ArrayEntry(items) = ArrayEntry(items,Dict{Int,Int}(),0)

function Base.show(io::IO, e::ArrayEntry; pad = [], key = "")
  c = COLORS[(length(pad)%length(COLORS))+1]
  # paddedprint(io,"Vector with $(length(e.items)) items(s). (updated = $(e.updated))\n", color=c)
  if isnothing(e.items)
	paddedprint(io, "$(key): [Empty List] (updated = $(e.updated))\n", color=c)
	return
  end
  paddedprint(io,"$(key): [List] (updated = $(e.updated))\n", color=c)
  paddedprint(io, "  └── ", color=c, pad=pad)
  show(io, e.items, pad = [pad; (c, "      ")])
end

function update!(a::ArrayEntry, b::Vector)
	n = length(b)
	a.updated +=1
	a.l[n] = get(a.l,n,0) + 1
	n == 0 && return
	if isnothing(a.items)
		 a.items = newentry(b).items
	end
	# foreach(v -> update!(a.items,v), b)
	for v in b
		update!(a.items,v)
	end
end

function suggestextractor(node::ArrayEntry, settings = NamedTuple())
	if isnothing(node.items)
		throw(ArgumentError("empty array, can not suggest extractor"))
	end
	e = suggestextractor(node.items, settings)
	isnothing(e) ? e : ExtractArray(e)
end


function merge(es::ArrayEntry...)
	updates_merged = sum(map(x->x.updated, es))
	l_merged = merge(+, map(x->x.l, es)...)
	items_merged = merge(merge, map(x->x.items, es)...)
	ArrayEntry(items_merged, l_merged, updates_merged)
end

"""
		mutable struct DictEntry <: JSONEntry
			childs::Dict{String,Any}
			updated::Int
		end

		keeps statistics about an object in json
		`childs` maintains key-value statistics of childrens. All values should be JSONEntries
		`updated` counts how many times the struct was updated.
"""

mutable struct DictEntry <: JSONEntry
	childs::Dict{Symbol, Any}
	updated::Int
end

DictEntry() = DictEntry(Dict{Symbol,Any}(),0)
Base.getindex(s::DictEntry, k::Symbol) = s.childs[k]
Base.getindex(s::DictEntry, k::String) = s.childs[Symbol(k)]
Base.setindex!(s::DictEntry, i, k::Symbol) = s.childs[k] = i
Base.setindex!(s::DictEntry, i, k::String) = s.childs[Symbol(k)] = i
Base.get(s::Dict{Symbol, <:Any}, key::String, default) = get(s, Symbol(key), default)

function Base.show(io::IO, e::DictEntry; pad=[], key = "")
    c = COLORS[(length(pad)%length(COLORS))+1]
    k = sort(collect(keys(e.childs)))
    if isempty(k)
    	paddedprint(io, "$(key)[Empty Dict] (updated = $(e.updated))\n", color=c)
    	return
    end
    ml = maximum(length.(k))
    key *= ": "
	  paddedprint(io, "$(key)[Dict] (updated = $(e.updated))\n", color=c)

    for i in 1:length(k)-1
    	s = "  ├──"*"─"^(ml-length(k[i]))*" "
			paddedprint(io, s, color=c, pad=pad)
			show(io, e.childs[k[i]], pad=[pad; (c, "  │"*" "^(ml-length(k[i])+2))], key = string(k[i]))
    end
    s = "  └──"*"─"^(ml-length(k[end]))*" "
    paddedprint(io, s, color=c, pad=pad)
    show(io, e.childs[k[end]], pad=[pad; (c, " "^(ml-length(k[end])+4))], key = string(k[end]))
end

function update!(s::DictEntry,d::Dict)
	s.updated +=1
	for (k,v) in d
		v == nothing && continue
		i = get(s.childs, k, newentry(v))
		update!(i,v)
		s[k] = i
	end
end


"""
		suggestextractor(e::DictEntry, settings = NamedTuple())

		create convertor of json to tree-structure of `DataNode`

		`e` top-level of json hierarchy, typically returned by invoking schema
		`settings.mincount` contains minimum repetition of the key to be included into
		the extractor (if missing it is equal to zero)
		`settings` can be any container supporting `get` function
"""
function suggestextractor(e::DictEntry, settings = NamedTuple())
	mincount = get(settings, :mincount, 0)
	ks = Iterators.filter(k -> updated(e.childs[k]) > mincount, keys(e.childs))
	isempty(ks) && return(nothing)
	c = [(k,suggestextractor(e.childs[k], settings)) for k in ks]
	c = filter(s -> s[2] != nothing, c)
	isempty(c) && return(nothing)
	mask = map(i -> extractsmatrix(i[2]), c)
	ExtractBranch(Dict(c[mask]),Dict(c[.! mask]))
end


function merge(es::DictEntry...)
	updates_merged = sum(map(x->x.updated, es))
	childs_merged = merge(merge, map(x->x.childs, es)...)
	DictEntry(childs_merged, updates_merged)
end


"""
		newentry(v)

		creates new entry describing json according to the type of v
"""
newentry(v::Dict) = DictEntry()
newentry(v::A) where {A<:StringOrNumber} = Entry()
newentry(v::Vector) = isempty(v) ? ArrayEntry(nothing) : ArrayEntry(newentry(v[1]))

"""
		function schema(a::Vector{T}) where {T<:Dict}
		function schema(a::Vector{T}) where {T<:AbstractString}

		create schema from an array of parsed or unparsed JSONs
"""
function schema(a::Vector{T}) where {T<:Dict}
	schema = DictEntry()
	foreach(f -> update!(schema,f),a)
	schema
end

function schema(a::Vector{T}) where {T<:AbstractString}
	schema = DictEntry()
	foreach(f -> update!(schema,JSON.parse(f)), a)
	schema
end

updated(s::T) where {T<:JSONEntry} = s.updated
merge(combine::typeof(merge), es::JSONEntry...) = merge(es...)

sample_synthetic(e::Entry) = first(keys(e.counts))
sample_synthetic(e::ArrayEntry) = repeat([sample_synthetic(e.items)], 2)
sample_synthetic(e::DictEntry) = Dict(k => sample_synthetic(v) for (k, v) in e.childs)

reflectinmodel(sch::JSONEntry, ex::AbstractExtractor, db, da=d->SegmentedMean(d); b = Dict(), a = Dict()) =
	reflectinmodel(ex(sample_synthetic(sch)), db, da, b=b, a=a)
