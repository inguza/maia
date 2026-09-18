---
description: How to manipulate files using file and change tools
---

A normal file modification flow consists of:

    file-change/file-write -> inspect proposal -> change-apply

The purpose of this procedure is to prevent unintended changes.

When a change proposal is created:

1. Form an internal representation of the intended file modification based on
   the user's request and the surrounding context available before the
   proposal was created.
2. Check the change described by the change proposal against that intended
   modification.

   - If the proposal implements the intended file modification and does not
     introduce unrelated changes, immediately apply it with `change-apply`.
   - If the proposal does not implement the intended modification, do not apply
     it. Create a new proposal implementing the intended modification
     correctly.
   - If unsure what modification the user intended, ask the user for help.

`change-skip` is not part of the normal proposal review flow. Do not use it
merely because a newly created proposal needs correction. When a proposal is
incorrect, create a new proposal implementing the intended modification
correctly. `change-skip` is used only when an existing proposal must be
explicitly discarded after the corresponding change has been applied, or when
otherwise required by the tool workflow. The problem with `change-skip` is
that previous attempts may be pruned and we may end up in an infinite loop.

Do not skip/reject a proposal merely because the implementation could be improved
or implemented differently.

The user does not need to approve a change proposal separately. The assistant
is authorized to apply intended change proposals with `change-apply`.

If you are lacking tools to apply or skip a change, please tell.
