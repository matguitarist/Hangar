# Recipes

`recipes.json` is the recipe manifest bundled with Hangar (`build.sh` copies it to
`Contents/Resources`). Each entry is checked on load and a bad one is skipped, never fatal:
the Log page lists what was skipped and why. The fields are in `Sources/HangarKit/Recipes.swift`;
`Tests/Fixtures/recipes.json` has a full example.

A recipe only goes in once someone has tested it on a real Mac: `tested` names the runner
and version, `source` who tested it. Paths are `@bottle/…` or `@game/…`, never absolute.
