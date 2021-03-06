### A Pluto.jl notebook ###
# v0.10.0

using Markdown

# ╔═╡ ec89f332-bb8c-439f-b5f0-202a23308e12
md"""
# Data checking: consistency

A common task in data cleaning or data checking is to establish consistency in columns of values that should be a property of another column of keys.
Suppose, for example, that a longitudinal data set collected on several `subject`s over time also contains a column for the subject's `gender`.
We should check that the gender is recorded consistently for each subject.
(Inconsistently recorded gender may be a choice by a non-binary person but most of the time it is a data error.)

We will use data from the [ManyBabies study](https://github.com/manybabies/mb1-analysis-public/) to illustrate such checks.
This is a valuable data set because the investigators in the study documented the original data and the steps in cleaning it.

First load the packages to be used.
"""

# ╔═╡ ff373d15-7311-4653-99c6-cf1c584796d7
using Arrow, CSV, DataFrames, HTTP, Tables

# ╔═╡ 51a8706e-9118-4ef4-9556-278aca0dffd7
md"""
The data table we will consider is `processed_data/02_validated_output.csv`.
It can be read directly from github (after `using HTTP`) with
"""

# ╔═╡ 467715fe-8950-4a0a-8ab4-5a752c1dc5c7
f = CSV.File(
    HTTP.get("https://github.com/manybabies/mb1-analysis-public/raw/master/processed_data/02_validated_output.csv").body,
    missingstrings = ["NA"],
	truestrings = ["TRUE"],
	falsestrings = ["FALSE"],
);

# ╔═╡ af6a751a-fbda-460c-b720-cc9442419927
md"""
## Data Tables

The packages developed by the [JuliaData group](https://github.com/JuliaData/) provide both column-oriented tables, similar to `data.frame` or `tibble` in `R` or `pandas` data frame in `Python`, or row-oriented tables, such as returned from queries to relational database systems.
The [Tables package](https://github.com/JuliaData/Tables.jl) provides the glue between the two representations.

The value returned by `CSV.File` iterates efficient row "views", but stores the data internally in columns.
"""

# ╔═╡ 32c7f89a-3a23-4695-a5b4-ecded311d9c1
length(f)

# ╔═╡ 31e273e9-e831-4ddb-b989-efd6f543d517
schem = Tables.schema(f)

# ╔═╡ 50cf00c6-ddbc-48fb-af89-0c784c053335
md"""
`f` can be converted to a generic column-oriented table with `Tables.columntable`
"""

# ╔═╡ 99750cc9-8e86-49d2-9de1-7aab69d28c71
ct = Tables.columntable(f)

# ╔═╡ 432bd0f2-81e9-4f31-ba1f-0c90e77672e7
typeof(ct)

# ╔═╡ c30a26dc-c0f9-426a-8914-c0b2eb663025
md"""
which is a `NamedTuple`, somewhat like a `list` in `R`.
This is an immutable structure in the sense that the names and the locations of the vectors representing the columns cannot be changed.
The values in the vectors can be modified but the structure can't.

A `DataFrame`, provided by the [DataFrames package](https://github.com/JuliaData/DataFrames.jl), is mutable.  The package provides facilities comparable to the tidyverse or pandas.
For example, we use a GroupedDataFrame below to access rows containing a specific `subid`.
"""

# ╔═╡ 33d30241-45a0-4d8e-90b3-6436a6b65420
begin
	df = DataFrame(ct);
	describe(df)
end
# ╔═╡ d8fca1cd-b43b-45a4-91e6-d49b291ff0e2
md"""
## Checking for inconsistent values

The general approach in pandas or tidyverse is to manipulate columns.
In Julia we can choose either row-oriented or column-oriented because the `Tables` interface incorporates both.

One assumption about these data was that the `subid` was unique to each baby.
It turns out that was not the case, which is why the `subid_unique` was created.
Different `lab`s used the same `subid` forms.

To check for unique values in a `value` column according to a `key` column we can iterate over the vectors and store the first value associated with each key in a dictionary.
For each row if a value is stored and it is different from the current value the key is included in the set of inconsistent keys.
(A `Set` is used rather than a `Vector` to avoid recording the same key multiple times.)

A method defined for two vectors could be
"""

# ╔═╡ e3381cf3-5b2b-4f8b-be21-2459d4181975
begin
	function inconsistent(keycol, valuecol)
		dict = Dict{eltype(keycol), eltype(valuecol)}()
		set = Set{eltype(keycol)}()
		for (k,v) in zip(keycol, valuecol)
			if haskey(dict, k) && dict[k] ≠ v
				push!(set, k)
			else
				dict[k] = v
			end
		end
		set
	end
	inconsistent(df.subid, df.lab)
end

# ╔═╡ 46bf3f16-16d0-433e-b5ba-d3e743712b05
md"""
A row-oriented approach would simply iterate over the rows
"""

# ╔═╡ e7dcd9d0-4bd3-4953-950c-68bdec4eef67
let dict = Dict()
	set = Set()
	for r in Tables.rows(f)
		get!(dict, r.subid, r.lab) ≠ r.lab && push!(set, r.subid)
	end
	set
end

# ╔═╡ 9b0c9a59-008e-4bcb-92f0-b47f5d41b4b6
md"""
Note that the returned value is a `Set{Any}` as we did not specify an element type in the constructor.

This code chunk uses the `get!` method for a `Dict`, which combines the effect of `haskey`, `setindex` and `getindex`. It also uses the short-circuiting boolean AND, `&&`.

The same effect can be achieved by the "lazy" evaluator `Tables.columns` which creates the effect of having columns as vectors.
"""

# ╔═╡ 8e163074-59ae-4bd9-8d23-83af3115ecdd
begin
	function inconsistent(tbl, keysym::Symbol, valuesym::Symbol)
		ctbl = Tables.columns(tbl)
		inconsistent(getproperty(ctbl, keysym), getproperty(ctbl, valuesym))
	end
	inconsistent(f, :subid, :lab)
end

# ╔═╡ 8938b29d-ac9e-48f4-9387-b8eef12ed2e4
md"""
Finally we can go back and rewrite a more specific method for vectors using templated types.
"""

# ╔═╡ 54c081e6-677b-4ece-835a-670a0bf9456a
dupids = begin
	function inconsistent(kvec::AbstractVector{T}, vvec::AbstractVector{S}) where {T,S}
		dict = Dict{T,S}()
		set = Set{T}()
		for (k, v) in zip(kvec, vvec)
			get!(dict, k, v) ≠ v && push!(set, k)
		end
		set
	end
	inconsistent(ct.subid, ct.lab)
end
# ╔═╡ 72b2f435-6b39-4414-8c9c-1874d7c8e2db
md"""
or, passing the Table and column names,
"""

# ╔═╡ b76879aa-4ae5-4cdd-b9d1-efa9992816ee
inconsistent(f, :subid, :lab)

# ╔═╡ 0defcb99-3d49-4b43-9840-17801646dcc7
md"""
Unfortunately, we are not quite finished.
As frequently happens in data science, missing data values will complicate things.

For example, some of the values in the `preterm` column are missing.
"""

# ╔═╡ 3499dc13-e29e-4b0a-91aa-21df9fcb3f5e
unique(f.preterm)

# ╔═╡ 3e2e956a-b521-448d-9adb-ad2655636e60
md"""
and if we try to check for consistency these values cause an error
"""

# ╔═╡ a1c1230d-078a-409f-8ccc-e3de594a1fb9
inconsistent(f, :subid, :preterm)

# ╔═╡ f5983b96-552b-4da6-9bf0-664e1d477eba
md"""
The problem stems from comparison with values that may be missing.
Most comparisons will, necessarily, return missing.
The only function guaranteed to return a logical value for an argument of `missing` is `ismissing`.

We could add code to check for missing values and take appropriate action but another approach shown below allows us to side-step this problem.

## Using DataFrames to check consistency

If I were just checking for consistency in R I would `select` the key and value columns, find the `unique` rows and check the number of rows against the number of keys.  The same approach could be used with the `DataFrames` package.
"""

# ╔═╡ 74631e26-becf-45c9-9941-59cb37462092
nrow(unique(select(df, [:lab, :subid])))

# ╔═╡ 2f5b9b04-69c8-4682-bc9d-2860e5ef832b
select(df, [:lab, :subid]) |> unique |> nrow # if you feel you must use pipes

# ╔═╡ 1bbfe575-1c01-4e91-b47a-1a8693d66b8d
length(unique(df.subid))

# ╔═╡ 815c44ac-ad6f-47e6-8e7c-3839119d3f3a
md"""
This brings up a couple of "variations on a theme" for the Julia version.  Suppose we just wanted to check if the values are consistent with the keys.  Then we can short-circuit the loop.
"""

# ╔═╡ bdaca49e-786a-4198-9af7-b4c6a0975b30
begin
	function isconsistent(kvec::AbstractVector{T}, vvec::AbstractVector{S}) where {T,S}
		dict = Dict{T,S}()
		for (k, v) in zip(kvec, vvec)
			get!(dict, k, v) ≠ v && return false
		end
		true
	end
	isconsistent(ct.subid, ct.lab)
end

# ╔═╡ f8159891-f7bd-4852-b422-8c9b697bc93a
md"""
Alternatively, suppose we wanted to find all the `lab`s that used a particular `subid`.
"""

# ╔═╡ d3fc587f-84c1-4405-a96f-9dd982d20bd3
begin
	function allvals(kvec::AbstractVector{T}, vvec::AbstractVector{S}) where {T,S}
		dict = Dict{T,Set{S}}()
		for (k, v) in zip(kvec, vvec)
			push!(get!(dict, k, Set{S}()), v)
		end
		dict
	end
	setslab = allvals(ct.subid, ct.lab)
end
# ╔═╡ 68a5fa64-b46e-40ac-87c9-f16e3f4ed101
md"""
This allows us to get around the problem of missing values in the `preterm` column.
"""

# ╔═╡ ba000ae0-a20f-4037-9ece-d9411aa4d221
setspreterm = allvals(f.subid_unique, f.preterm)

# ╔═╡ dd9064f1-0ecd-463f-b58a-4fa47627667d
repeatedlab = filter(pr -> length(last(pr)) > 1, setslab)

# ╔═╡ 6234c50f-90d0-477f-9c86-429bf1590518
md"""
The construction using `->` (sometimes called a "stabby lambda") creates an anonymous function.
The argument to this function will be a `(key, value)` pair and `last(pr)` extracts the value, a `Set{String}` in this case.
"""

# ╔═╡ dc3ef214-5531-46c7-baab-f250f3d71160
md"""
`preterm`, on the other hand, is coded consistently for each `subid_unique`.
"""

# ╔═╡ ab193913-7776-4483-b6a2-3700b42319b2
repeatedpreterm = filter(pr -> length(last(pr)) > 1, setspreterm)

# ╔═╡ b12da7d5-41a1-40ca-bcaf-8b234cc0d6cf
md"""
## Extracting the inconsistent cases

The `DataFrames` package provides a `groupby` function to create a `GroupedDataFrame`.
Generally it is use in a split-apply-combine strategy but it can be used to extract subsets of rows according to the values in one or more columns.
It is effective if the operation is to be repeated for different values, such as here.
"""

# ╔═╡ 6b008853-9a2c-4eff-9885-ff034cd4b993
begin
	gdf = groupby(df, :subid);
	typeof(gdf)
end

# ╔═╡ ab3ca35a-7c30-4c53-a98f-77f31db7efa5
g1 = gdf[(subid = "1",)]

# ╔═╡ b40031ba-d4c5-40fe-9960-5f30b3423bca
unique(g1.lab)

# ╔═╡ 31e51339-e3b6-44f3-88fd-2e0fc8b5c666
md"""
## Summary

The point of this example is not that one should expect to custom program each step in a data cleaning operation.
The facilities in the `DataFrames` package could be used in a tidyverse-like approach.

However, if the particular tool for a task is not available or, more likely, you don't know offhand where it is and what it is called, there are low-level tools easily available.
And using the low-level tools inside of loops doesn't impede performance.

As a last action in this notebook, we will save the table as an `Arrow` file that will be used in the next notebook.

Arrow files can be written with or without compression.
As may be expected, the file size of the compressed version is smaller but it takes longer to read it because it must be uncompressed.
"""

# ╔═╡ 23db4642-ad43-434b-a48c-4b8588f1e79e
Arrow.write("02_validated_output.arrow", f);

# ╔═╡ 71b2c810-1d3b-4b86-bd8f-4540e2073195
filesize("02_validated_output.arrow")

# ╔═╡ b331ebc6-de4c-4c95-a283-3fcb362a2dab
Arrow.write("02_validated_output_compressed.arrow", f, compress = :zstd)

# ╔═╡ 199835fd-7793-42a5-b52c-16ea711cf350
filesize("02_validated_output_compressed.arrow")

# ╔═╡ Cell order:
# ╟─ec89f332-bb8c-439f-b5f0-202a23308e12
# ╠═ff373d15-7311-4653-99c6-cf1c584796d7
# ╟─51a8706e-9118-4ef4-9556-278aca0dffd7
# ╠═467715fe-8950-4a0a-8ab4-5a752c1dc5c7
# ╟─af6a751a-fbda-460c-b720-cc9442419927
# ╠═32c7f89a-3a23-4695-a5b4-ecded311d9c1
# ╠═31e273e9-e831-4ddb-b989-efd6f543d517
# ╟─50cf00c6-ddbc-48fb-af89-0c784c053335
# ╠═99750cc9-8e86-49d2-9de1-7aab69d28c71
# ╠═432bd0f2-81e9-4f31-ba1f-0c90e77672e7
# ╟─c30a26dc-c0f9-426a-8914-c0b2eb663025
# ╠═33d30241-45a0-4d8e-90b3-6436a6b65420
# ╟─d8fca1cd-b43b-45a4-91e6-d49b291ff0e2
# ╠═e3381cf3-5b2b-4f8b-be21-2459d4181975
# ╟─46bf3f16-16d0-433e-b5ba-d3e743712b05
# ╠═e7dcd9d0-4bd3-4953-950c-68bdec4eef67
# ╟─9b0c9a59-008e-4bcb-92f0-b47f5d41b4b6
# ╠═8e163074-59ae-4bd9-8d23-83af3115ecdd
# ╟─8938b29d-ac9e-48f4-9387-b8eef12ed2e4
# ╠═54c081e6-677b-4ece-835a-670a0bf9456a
# ╟─72b2f435-6b39-4414-8c9c-1874d7c8e2db
# ╠═b76879aa-4ae5-4cdd-b9d1-efa9992816ee
# ╟─0defcb99-3d49-4b43-9840-17801646dcc7
# ╠═3499dc13-e29e-4b0a-91aa-21df9fcb3f5e
# ╟─3e2e956a-b521-448d-9adb-ad2655636e60
# ╠═a1c1230d-078a-409f-8ccc-e3de594a1fb9
# ╟─f5983b96-552b-4da6-9bf0-664e1d477eba
# ╠═74631e26-becf-45c9-9941-59cb37462092
# ╠═2f5b9b04-69c8-4682-bc9d-2860e5ef832b
# ╠═1bbfe575-1c01-4e91-b47a-1a8693d66b8d
# ╟─815c44ac-ad6f-47e6-8e7c-3839119d3f3a
# ╠═bdaca49e-786a-4198-9af7-b4c6a0975b30
# ╟─f8159891-f7bd-4852-b422-8c9b697bc93a
# ╠═d3fc587f-84c1-4405-a96f-9dd982d20bd3
# ╟─68a5fa64-b46e-40ac-87c9-f16e3f4ed101
# ╠═ba000ae0-a20f-4037-9ece-d9411aa4d221
# ╠═dd9064f1-0ecd-463f-b58a-4fa47627667d
# ╟─6234c50f-90d0-477f-9c86-429bf1590518
# ╟─dc3ef214-5531-46c7-baab-f250f3d71160
# ╠═ab193913-7776-4483-b6a2-3700b42319b2
# ╟─b12da7d5-41a1-40ca-bcaf-8b234cc0d6cf
# ╠═6b008853-9a2c-4eff-9885-ff034cd4b993
# ╠═ab3ca35a-7c30-4c53-a98f-77f31db7efa5
# ╠═b40031ba-d4c5-40fe-9960-5f30b3423bca
# ╟─31e51339-e3b6-44f3-88fd-2e0fc8b5c666
# ╠═23db4642-ad43-434b-a48c-4b8588f1e79e
# ╠═71b2c810-1d3b-4b86-bd8f-4540e2073195
# ╠═b331ebc6-de4c-4c95-a283-3fcb362a2dab
# ╠═199835fd-7793-42a5-b52c-16ea711cf350
