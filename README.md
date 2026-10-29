# When a prototype becomes critical, does your GitHub policy know?

Configuration from the GitHub Universe 2026 session by Baruch Sadogursky (Port).

Printf is a fictional swag company. Its `size-catalog` started as Austin's
sizing helper, a prototype one factory used. The day Berlin and Osaka started
using it too, Port marked it critical, wrote that to GitHub as an external custom property,
and an organization ruleset that targets `Port.criticality=critical` started
requiring two reviews on a pull request that had already met the old rules.

Nobody typed "critical". Adoption did.

## What's in here

| Path | What it does |
| --- | --- |
| `port/blueprint-service-additions.json` | `criticality`, `lifecycle` and `consumers` on the service blueprint, plus its relation to the GitHub repository |
| `port/blueprint-factory.json` | The consumers: one factory per print site, with a `uses` relation to the services it calls |
| `port/workflow-adoption_sets_criticality.json` | When a factory's `uses` changes, count the factories using that service and set its criticality (one factory: low, it's that factory's prototype; two or more: critical) |
| `port/workflow-sync_gh_external_props.json` | When a service's owner, lifecycle or criticality changes, write them to `Port.owner`, `Port.lifecycle` and `Port.criticality` on its repository |
| `port/workflow-resync_service_to_github.json` | Self-service: re-send one service's values to GitHub |
| `github/ruleset-baseline.json` | Every repository: pull requests with one approval on the default branch |
| `github/ruleset-critical.json` | Repositories where `Port.criticality` is `critical`: two approvals, passing `test` check, no force pushes, no deletion |
| `scripts/reset-demo.sh` | Puts the demo back to its opening state and verifies every step |

## Try it on one repository

You need a GitHub organization on Team or Enterprise (organization rulesets
return `403 Upgrade to GitHub Team` on Free) and a Port organization.

1. **Connect GitHub to Port** with the GitHub (Ocean) integration and approve
   *External custom properties for repositories: Admin* during installation.
   That permission is what lets Port claim the `Port` namespace in your
   organization. Without it every write fails with a 422.
2. **Add the service properties.** Merge `port/blueprint-service-additions.json`
   into your service blueprint and relate one service to its repository.
3. **Import the sync workflow.** Paste `port/workflow-sync_gh_external_props.json`
   into Port's workflow JSON editor and replace `printf-swag` with your
   organization and `github-ocean` with your integration's installation ID.
4. **Change the service's criticality in Port**, then read it back from GitHub:

   ```bash
   gh api repos/YOUR_ORG/YOUR_REPO/properties/values
   ```

   Expect `Port.criticality`, `Port.lifecycle` and `Port.owner`. They show in
   the repository's settings with a plug icon and can't be edited in GitHub.
5. **Create the ruleset**, replacing nothing but the org:

   ```bash
   gh api -X POST orgs/YOUR_ORG/rulesets --input github/ruleset-critical.json
   ```

   Before you widen it, open a test pull request with one approval on the
   critical repository and check that GitHub asks for a second.

   ```bash
   gh api repos/YOUR_ORG/YOUR_REPO/rules/branches/main
   ```

   lists every rule that applies to the branch and which ruleset it comes from.

## Things we learned building it

- The sync only reacts to changes after the workflow exists. Use the resync
  workflow, or edit the value once, to backfill.
- Port's aggregation properties recalculate on a 15-minute schedule. That's
  fine for dashboards and too slow for a policy change you expect to see in
  seconds, so the adoption workflow counts consumers itself.
- Filter repositories in GitHub with `props.Port.criticality:critical`. If that
  returns nothing, the ruleset matches nothing.
- Port's GitHub integration action occasionally failed without a reason during
  rehearsal. The sync workflow writes, re-reads the service, and writes again
  twice; a repeated write of the current values is harmless.
- An owning-team property makes repositories findable. It isn't access control
  and it doesn't write CODEOWNERS.

## Links

- [Sync Port properties to GitHub external custom properties](https://docs.port.io/guides/all/sync-port-properties-to-github-external-custom-properties/)
- [GitHub: sync external custom properties](https://docs.github.com/en/organizations/managing-organization-settings/sync-external-custom-properties)
- [GitHub: creating rulesets for repositories in your organization](https://docs.github.com/en/organizations/managing-organization-settings/creating-rulesets-for-repositories-in-your-organization)
