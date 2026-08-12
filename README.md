<div align="center">
  <img src="content/assets/branding/Billboard.svg" alt="Template" width="860">
  <h3>A reusable foundation for source, automation, documentation, and publication.</h3>

  <p>
    <a href="https://github.com/Kooraseru/Template"><img alt="Stars + Issues + License" src="https://shieldcn.dev/group/github/stars/Kooraseru/Template+github/Kooraseru/Template/issues+github/license/Kooraseru/Template.svg?variant=outline"></a>
  </p>

  <img src="https://counter.seku.su/cmoe?name=Kooraseru&theme=mb" alt="Visitor counter">

  <table>
    <tr>
      <td align="center"><a href="#features">Features</a></td>
      <td align="center"><a href="#quick-start">Quick Start</a></td>
      <td align="center"><a href="#documentation">Documentation</a></td>
      <td align="center"><a href="#project">Project</a></td>
    </tr>
  </table>

  <table>
  <tr>
    <td align="center"><a href="README.md">English</a></td>
    <td align="center"><a href="docs/README.ja-JP.md">日本語</a></td>
  </tr>
</table>
</div>

<h2 id="features">Features</h2>

- Clear boundaries between authored source, private workspace state, and generated output.
- Reusable GitHub issue intake, dependency management, validation, and publication automation.
- Project documentation built with MkDocs and confined to `.generated/site/`.
- Shared VS Code launch, task, extension, snippet, and portable MCP templates.
- Automation-owned `canary`, `beta`, and `stable` branches derived from immutable `source` commits.

<h2 id="quick-start">Quick Start</h2>

1. Create a repository from this template using the maintainer-approved template-copy workflow.
2. Replace the Template name, description, wordmark, links, and project-specific guidance.
3. Read the [published documentation](https://kooraseru.github.io/Template/) and [contribution guide](.github/CONTRIBUTING.md).
4. Add only the source domains, tests, dependencies, and public content the project uses.
5. Configure publication, GitHub Pages, environments, signing, and CodeQL only when the project needs them.
6. Run the repository validation tasks before opening a pull request against `source`.

Publication uses the explicit public-file whitelist in `.github/publication/config.yml`. Projects should adjust that whitelist as their public surfaces change.

<h2 id="documentation">Documentation</h2>

<table>
  <tr><td><a href=".github/CONTRIBUTING.md"><code>.github/CONTRIBUTING.md</code></a></td><td>Defines the contributor workflow.</td></tr>
  <tr><td><a href=".github/SECURITY.md"><code>.github/SECURITY.md</code></a></td><td>Defines private vulnerability reporting.</td></tr>
  <tr><td><a href="https://kooraseru.github.io/Template/">Published documentation</a></td><td>Provides the generated documentation site.</td></tr>
</table>

<h2 id="project">Project</h2>

Template is maintained as a reusable repository baseline. Projects created from it should replace template identity and retain only capabilities with a responsible maintainer and active consumer.

### Branches

<table>
  <tr><td><code>source</code></td><td>Canonical authoring branch</td></tr>
  <tr><td><code>canary</code></td><td>Generated earliest-consumption channel</td></tr>
  <tr><td><code>beta</code></td><td>Generated testing channel</td></tr>
  <tr><td><code>stable</code></td><td>Generated production channel</td></tr>
</table>

Contributors author changes and target pull requests at `source`. Automation owns the generated branches.

### License

Licensed under the [Observer License 0.1](https://github.com/Kooraseru/Observer-License).

### Contributors

<a href="https://github.com/Kooraseru/Template/graphs/contributors" target="_blank">
  <img src="https://contrib.rocks/image?repo=Kooraseru/Template" alt="Template contributors">
</a>
