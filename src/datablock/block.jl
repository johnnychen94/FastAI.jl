"""
    abstract type AbstractBlock

Abstract supertype of all blocks. You should not subtype form this,
but instead from [`Block`](#) or [`WrapperBlock`](#).
"""
abstract type AbstractBlock end


"""
    abstract type Block

A block describes the meaning of a piece of data in the context of a learning task.
For example, for supervised learning tasks, there is an input and a target
and we want to learn to predict targets from inputs. Learning to predict a
cat/dog label from 2D images is a supervised image classification task that can
be represented with the `Block`s `Image{2}()` and `Label(["cat", "dog"])`.

`Block`s are used in virtually every part of the high-level interfaces, from data
processing over model creation to visualization.

## Extending

Consider the following when subtyping `Block`. A block

- Does not hold observation data itself. Instead they are used in conjunction with
  data to annotate it with some meaning.
- If it has any fields, they should be metadata that cannot be
  derived from the data itself and is constant for every sample in
  the dataset. For example `Label` holds all possible classes which
  are constant for the learning problem.

### Interfaces

There are many interfaces that can be implemented for a `Block`. See the docstrings
of each function for more info about how to implement it.

- [`checkblock`](#)`(block, obs)`: check whether an observation is a valid block
- [`mockblock`](#)`(block)`: randomly generate an observation
- [`blocklossfn`](#)`(predblock, yblock)`: loss function for comparing two blocks
- [`blockmodel`](#)`(inblock, outblock[, backbone])`: construct a task-specific model
- [`blockbackbone`](#)`(inblock)`: construct a backbone model that takes in specific data
- [`showblock!`](#)`(block, obs)`: visualize an observation

"""
abstract type Block <: AbstractBlock end


"""
    checkblock(block, obs)
    checkblock(blocks, obss)

Check whether `obs` is compatible with `block`, returning a `Bool`.

## Examples

```julia
checkblock(Image{2}(), rand(RGB, 16, 16)) == true
```

```julia
checkblock(
    (Image{2}(),        Label(["cat", "dog"])),
    (rand(RGB, 16, 16), "cat"                ),
) == true
```

## Extending

An implementation of `checkblock` should be as specific as possible. The
default method returns `false`, so you only need to implement methods for valid types
and return `true`.
"""
checkblock(::Block, obs) = false

function checkblock(blocks::Tuple, obss::Tuple)
    @assert length(blocks) == length(obss)
    return all(checkblock(block, obs) for (block, obs) in zip(blocks, obss))
end


"""
    mockblock(block)
    mockblock(blocks)

Randomly generate an instance of `block`. It always holds that
`checkblock(block, mockblock(block)) === true`.
"""
mockblock(blocks::Tuple) = map(mockblock, blocks)


"""
    setup(Block, data)

Create an instance of block type `Block` from data container `data`.

## Examples

```julia
setup(Label, ["cat", "dog", "cat"]) == Label(["cat", "dog"])
```

    setup(Encoding, block, data; kwargs...)

Create an encoding using statistics derived from a data container `data`
with observations of block `block`. Used when some arguments of the encoding
are dependent on the dataset. `data` should be the training dataset. Additional
`kwargs` are passed through to the regular constructor of `Encoding`.

## Examples

```julia
(images, labels), blocks = loaddataset("imagenette2-160", (Image, Label))
setup(ImagePreprocessing, Image{2}(), images; buffered = false)
```

```julia
data, block = loaddataset("adult_sample", TableRow)
setup(TabularPreprocessing, block, data)
```
"""
function setup end


# ## Utilities

typify(T::Type) = T
typify(t::Tuple) = Tuple{map(typify, t)...}
typify(block::FastAI.AbstractBlock) = typeof(block)


# ## Invariants
#
# Invariants allow specifying properties that an instance of a data for a block
# should have in more detail and such that actionable error messages can be given.

"""
    invariant_checkblock(block; kwargs...)
    invariant_checkblock(blocks; kwargs...)

Create a `Invariants.Invariant` that can be used to check whether an
observation is a valid instance of `block`. This should always agree
with `checkblock` (i.e. `checkblock(block, obs)` implies that
`check(invariant_checkblock(block), obs)`). The invariant can however
be used to give much more detailed information about the problem and
be used to throw helpful error messages from functions that depend
on these properties.
"""
function invariant_checkblock end


# If `invariant_checkblock` is not implemented for a block, default to
# checking that `checkblock` returns `true`.

function invariant_checkblock(block::AbstractBlock; obsname = "obs", blockname = "block")
    return BooleanInvariant(
        obs -> checkblock(block, obs),
        "`$obsname` should be valid $(typeof(block))",
        _ -> """Expected `$obsname` to be a valid instance of block $blockname
        with above type, but `checkblock($blockname, $obsname)` returned `false`.
        This probably means that `$obsname` is not a valid instance of the
        block. Check `?$(typeof(block).name.name)` for more information on
        the block and what data is valid.
        """,
    )
end

# For tuples of blocks, the invariant is composed of the individuals' blocks
# invariants, passing only if all the child invariants pass.

function invariant_checkblock(blocks::Tuple; obsname = "obss", blockname = "blocks")
    return SequenceInvariant(
        [
            BooleanInvariant(
                obss -> (obss isa Tuple && length(obss) == length(blocks)),
                "$obsname should be a `Tuple` with $(length(blocks)) elements.",
                obss -> """Instead, got a `$(sprint(show, typeof(obss)))`"""),
            AllInvariant(
                [
                    WithContext(
                        obss -> obss[i],
                        invariant_checkblock(
                            blocks[i];
                            obsname = "$obsname[$i]",
                            blockname = "$blockname[$i]",
                        ),
                    ) for (i, block) in enumerate(blocks)
                ],
                name = "`$obsname` should be valid `$blockname`",
                description = ""
            )
        ],
        "For a tuple of blocks, an instance should be a tuple of valid instances",
        "",
    )

end