# Local act compatibility

Stock act 0.2.89 rejects the current artifact actions' optional MIME field and
unpadded Azure upload signatures. See upstream issues
https://github.com/nektos/act/issues/6114 and https://github.com/nektos/act/issues/6021.

This Dockerfile builds that release with the two narrowly scoped parsing fixes.
It fails if the expected source changes, so a future act upgrade needs review.
It does not change workflow execution or weaken receipt verification. The generated
executor is a development tool, not a project release package.

For Windows ARM64:

```sh
docker build -f fabricator/distribution/images/act/Dockerfile --output type=local,dest=build/tools/act .
build/tools/act/act.exe push
```

Set `TARGET_OS` and `TARGET_ARCH` build arguments for other hosts. The output name
remains `act.exe` on every platform. Configure GitHub Local Actions to use this
executable until an upstream release includes these fixes. No signing key or
GitHub token is needed to build or run it.
