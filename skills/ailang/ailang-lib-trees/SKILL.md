---
name: ailang-lib-trees
description: Library.Trees AVL and BTree with string keys. Load for AVL.Create/Insert/Search or BTree.Create(order)/Insert/Search. No Trees.new, no delete, no range.
---

# Library.Trees (ailang)

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.Trees.ailang`.

```
LibraryImport.Trees
LibraryImport.Arrays
```

Trees already imports Arrays (`Helpers.StringCopy`, `Array.*`).

**String keys (Address).** Values are also Address and **copied as C strings**. No integer keys. No `Trees.new`. No delete. No range, successor, predecessor, min/max, or free.

## AVL

Node: `[key, value, left, right, height, parent]` (48 bytes). Tree: `[root, size, compare_fn]`.

```
tree = AVL.Create()                          // empty
AVL.Insert(tree, key, value) → 1|0           // 1 = new, 0 = update value
AVL.Search(tree, key) → Address              // value string, or 0
```

Insert/update copies key and value. Existing value is deallocated on update.

Internals (do not call unless implementing): `CreateNode`, `GetHeight`, `UpdateHeight`, `GetBalance`, `RotateLeft`/`RotateRight`, `RebalanceAfterInsert`.

## BTree

Tree: `[root, order, size]`. Node: `[is_leaf, num_keys, keys, values, children, parent]`. Max keys = `2*order - 1`.

```
tree = BTree.Create(order)
BTree.Insert(tree, key, value) → 1|0         // 1 = new, 0 = update
BTree.Search(root, key) → Address            // takes NODE, not tree
```

Search the tree with `BTree.Search(Dereference(tree), key)`. Miss = 0.

Internals: `CreateNode`, `InsertNonFull`, `SplitChild`. Uses `ArrayCreate`/`ArrayGet`/`ArraySet` inside nodes.

No `AVL.Destroy` / `BTree.Destroy` / `*.Delete`.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. Licensed under SCSL.
