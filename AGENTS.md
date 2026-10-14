# AGENTS.md

## README hardware table

Keep the rows in "Supported hardware" grouped by status: ✅, then ❌, then ❓. Within each group, MediaTek, Realtek and Qualcomm cards come before Intel, since `iwlwifi` only supports Exclusive mode.

Only add a machine to a card's row if it tells readers something new: a PCI ID or mode result not yet listed, or a failure. Another machine with a listed PCI ID and the same result on a different distro or kernel is redundant, so leave it out of the table.
