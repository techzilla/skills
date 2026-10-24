---
name: kibana-alerting-rules
description: >
  Create and manage Kibana alerting rules via the elastic CLI or Terraform. Use when creating,
  updating, finding, or managing rule lifecycle (enable, disable, mute, snooze) or rules-as-code
  workflows.
metadata:
  author: techzilla
  version: 0.2.0
  derived_from: elastic/agent-skills v0.4.0 (Apache-2.0), modified
compatibility: Written for and verified against `elastic` CLI 0.7.0. Update procedure requires `jq`.
---

# Kibana Alerting Rules

## Core Concepts

A rule has three parts: **conditions** (what to detect), **schedule** (how often to check), and **actions** (what
happens when conditions are met). When conditions are met, the rule creates **alerts**, which trigger **actions** via
**connectors**.

## Environment Configuration

Operations run through the [`elastic` CLI](https://github.com/elastic/cli#configuration) **0.7.0**, which handles
authentication and the `kbn-xsrf` header. Run `elastic kb system get-status` to verify the connection; if it fails,
tell the user to configure a context with a `kibana` block, then stop. Do not guess credentials or call the HTTP API
directly. For a non-default space, use a context whose `kibana.url` ends in `/s/<space_id>` and select it with
`--use-context <name>`.

Body flags (`--params`, `--schedule`, `--actions`, …) take JSON. For full bodies, use `--input-file <file.json>` with the
request fields at the top level.

## Required Privileges

- `all` privileges for the appropriate Kibana feature (e.g., Stack Rules, Observability, Security)
- `read` privileges for Actions and Connectors (to attach actions to rules)

## Creating a Rule

### Required Fields

| Field          | Type   | Description                                                                                                                                           |
| -------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`         | string | Display name (does not need to be unique)                                                                                                             |
| `rule_type_id` | string | The rule type (e.g., `.es-query`, `.index-threshold`)                                                                                                 |
| `consumer`     | string | Owning app: `alerts`, `apm`, `discover`, `infrastructure`, `logs`, `metrics`, `ml`, `monitoring`, `securitySolution`, `siem`, `stackAlerts`, `uptime` |
| `params`       | object | Rule-type-specific parameters                                                                                                                         |
| `schedule`     | object | Check interval, e.g., `{"interval": "5m"}`                                                                                                            |

The CLI also requires `--id`; generate one (e.g., `uuidgen`) when the user gives none.

### Optional Fields

| Field         | Type        | Description                                                                                         |
| ------------- | ----------- | --------------------------------------------------------------------------------------------------- |
| `actions`     | array       | Actions to run when conditions are met (each references a connector)                                |
| `tags`        | array       | Tags for organizing rules                                                                           |
| `enabled`     | boolean     | Whether the rule runs immediately (default: true)                                                   |
| `notify_when` | string      | `onActionGroupChange`, `onActiveAlert`, or `onThrottleInterval` (prefer setting per-action instead) |
| `alert_delay` | object      | Alert only after N consecutive matches, e.g., `{"active": 3}`                                       |
| `flapping`    | object/null | Override flapping detection settings                                                                |

### Example: Create an Elasticsearch Query Rule

`rule.json`:

```json
{
  "name": "High error rate",
  "rule_type_id": ".es-query",
  "consumer": "stackAlerts",
  "schedule": { "interval": "5m" },
  "params": {
    "index": ["logs-*"],
    "timeField": "@timestamp",
    "esQuery": "{\"query\":{\"match\":{\"log.level\":\"error\"}}}",
    "threshold": [100],
    "thresholdComparator": ">",
    "timeWindowSize": 5,
    "timeWindowUnit": "m",
    "size": 100
  },
  "actions": [
    {
      "id": "my-slack-connector-id",
      "group": "query matched",
      "params": { "message": "Alert: {{rule.name}} - {{context.hits}} hits detected" },
      "frequency": { "summary": false, "notify_when": "onActionGroupChange" }
    }
  ],
  "tags": ["production", "errors"]
}
```

```bash
elastic kb alerting post-alerting-rule-id --id '<rule-id>' --input-file rule.json
```

The same structure applies to other rule types — set the appropriate `rule_type_id` (e.g., `.index-threshold`,
`.es-query`) and provide the matching `params` object. Use `elastic kb alerting get-rule-types` to discover params
schemas, consumers, and action groups (stack only; see [Operations](#operations)).

## Updating a Rule

PUT replaces the rule and accepts only `name`, `tags`, `schedule`, `params`, `actions`, `alert_delay`, `flapping`,
`artifacts`, `notify_when`, `throttle`. `rule_type_id` and `consumer` are immutable. Fetch, strip read-only fields, edit,
then put:

```bash
elastic kb alerting get-alerting-rule-id --id '<rule-id>' | jq '{name, tags, schedule, params,
  actions: [.actions[]? | {id, group, params, frequency, uuid, alerts_filter, use_alert_data_for_template}
    | with_entries(select(.value != null))], alert_delay, flapping, artifacts, notify_when, throttle}
  | with_entries(select(.value != null)) | if any(.actions[]; .frequency) then del(.notify_when, .throttle) else . end' > rule.json
# edit rule.json
elastic kb alerting put-alerting-rule-id --id '<rule-id>' --input-file rule.json
```

Returns **409 Conflict** if another user updated the rule concurrently; re-fetch and retry.

## Finding Rules

```bash
elastic kb alerting get-alerting-rules-find --search cpu --search-fields name --sort-field name --sort-order asc \
  --per-page 20 --page 1
```

Also: `--filter` (KQL), `--default-search-operator`, `--fields`, `--filter-consumers`. Filter by tag:

```bash
elastic kb alerting get-alerting-rules-find --filter 'alert.attributes.tags:"production"'
```

`--has-reference` is mis-encoded by CLI 0.7.0. Pass it as a JSON string via `--input-file` with `--no-validate`:

```bash
echo '{"has_reference":"{\"type\":\"<type>\",\"id\":\"<id>\"}"}' > find.json
elastic kb alerting get-alerting-rules-find --input-file find.json --no-validate
```

## Lifecycle Operations

```bash
# Enable / disable (--body '{"untrack":true}' also untracks active alerts)
elastic kb alerting post-alerting-rule-id-enable --id '<rule-id>'
elastic kb alerting post-alerting-rule-id-disable --id '<rule-id>'

# Mute / unmute all alerts
elastic kb alerting post-alerting-rule-id-mute-all --id '<rule-id>'
elastic kb alerting post-alerting-rule-id-unmute-all --id '<rule-id>'

# Mute / unmute a specific alert
elastic kb alerting post-alerting-rule-rule-id-alert-alert-id-mute --rule-id '<rule-id>' --alert-id '<alert-id>'
elastic kb alerting post-alerting-rule-rule-id-alert-alert-id-unmute --rule-id '<rule-id>' --alert-id '<alert-id>'

# Snooze (Kibana 8.19+); add "recurring" or "timezone" inside "custom" as needed
elastic kb alerting post-alerting-rule-id-snooze-schedule --id '<rule-id>' \
  --schedule '{"custom":{"start":"2026-10-24T00:00:00.000Z","duration":"8h"}}'
elastic kb alerting delete-alerting-rule-ruleid-snooze-schedule-scheduleid --rule-id '<rule-id>' --schedule-id '<schedule-id>' --yes

# Delete
elastic kb alerting delete-alerting-rule-id --id '<rule-id>' --yes
```

## Terraform Provider

Use the `elasticstack` provider resource `elasticstack_kibana_alerting_rule`.

```hcl
terraform {
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
    }
  }
}

provider "elasticstack" {
  kibana {
    endpoints = ["https://my-kibana:5601"]
    api_key   = var.kibana_api_key
  }
}

resource "elasticstack_kibana_alerting_rule" "cpu_alert" {
  name         = "CPU usage critical"
  consumer     = "stackAlerts"
  rule_type_id = ".index-threshold"
  interval     = "1m"
  enabled      = true

  params = jsonencode({
    index              = ["metrics-*"]
    timeField          = "@timestamp"
    aggType            = "avg"
    aggField           = "system.cpu.total.pct"
    groupBy            = "top"
    termField          = "host.name"
    termSize           = 10
    threshold          = [0.9]
    thresholdComparator = ">"
    timeWindowSize     = 5
    timeWindowUnit     = "m"
  })

  tags = ["infrastructure", "production"]
}
```

**Key Terraform notes:**

- `params` must be passed as a JSON-encoded string via `jsonencode()`
- Use `elasticstack_kibana_action_connector` data source or resource to reference connector IDs in actions
- Import existing rules: `terraform import elasticstack_kibana_alerting_rule.my_rule <space_id>/<rule_id>` (use
  `default` for the default space)

## Triggering Kibana Workflows from Rules

> **Preview feature** — available from Elastic Stack 9.3 and Elastic Cloud Serverless. APIs may change.

Attach a workflow as a rule action using the workflow ID as the connector ID. Set `params: {}` — alert context flows
automatically through the `event` object inside the workflow. Add to `actions` in `rule.json` and run the
[update](#updating-a-rule) procedure:

```json
{
  "id": "<workflow-id>",
  "group": "query matched",
  "params": {},
  "frequency": { "summary": false, "notify_when": "onActionGroupChange" }
}
```

In the UI: **Stack Management > Rules > Actions > Workflows**. Only `enabled: true` workflows appear in the picker.

For workflow YAML structure, `{{ event }}` context fields, step types, and patterns, refer to the `kibana-connectors`
skill if available.

## Connectors and Actions in Rules

Each action references a connector by ID, an action `group`, action `params` (using Mustache templates), and a
per-action `frequency` object. Key fields:

- `group` — which trigger state fires this action (e.g., `"query matched"`, `"Recovered"`). Discover valid groups via
  `elastic kb alerting get-rule-types`.
- `frequency.summary` — `true` for a digest of all alerts; `false` for per-alert.
- `frequency.notify_when` — `onActionGroupChange` | `onActiveAlert` | `onThrottleInterval`.
- `frequency.throttle` — minimum repeat interval (e.g., `"10m"`); only applies with `onThrottleInterval`.

For full reference on action structure, Mustache variables (`{{rule.name}}`, `{{context.*}}`, `{{alerts.new.count}}`),
Mustache lambdas (`EvalMath`, `FormatDate`, `ParseHjson`), recovery actions, and multi-channel patterns, refer to the
`kibana-connectors` skill if available.

## Best Practices

1. **Set action frequency per action, not per rule.** The `notify_when` field at the rule level is deprecated in favor
   of per-action `frequency` objects. If you set it at the rule level and later edit the rule in the Kibana UI, it is
   automatically converted to action-level values.

2. **Use alert summaries to reduce notification noise.** Instead of sending one notification per alert, configure
   actions to send periodic summaries at a custom interval. Use `"summary": true` and set a `throttle` interval. This is
   especially valuable for rules that monitor many hosts or documents.

3. **Choose the right action frequency for each channel.** Use `onActionGroupChange` for paging/ticketing systems (fire
   once, resolve once). Use `onActiveAlert` for audit logging to an Index connector. Use `onThrottleInterval` with a
   throttle like `"30m"` for dashboards or lower-priority notifications.

4. **Always add a recovery action.** Rules without a recovery action leave incidents open in PagerDuty, Jira, and
   ServiceNow indefinitely. Use the connector's native close/resolve event action (e.g., `eventAction: "resolve"` for
   PagerDuty) in the `Recovered` action group.

5. **Set a reasonable check interval.** The minimum recommended interval is `1m`. Very short intervals across many rules
   clog Task Manager throughput and increase schedule drift. The server setting
   `xpack.alerting.rules.minimumScheduleInterval.value` enforces this.

6. **Use `alert_delay` to suppress transient spikes.** Setting `{"active": 3}` means the alert only fires after 3
   consecutive runs match the condition, filtering out brief anomalies.

7. **Enable flapping detection.** Alerts that rapidly switch between active and recovered are marked as "flapping" and
   notifications are suppressed. This is on by default but can be tuned per-rule with the `flapping` object.

8. **Use `server.publicBaseUrl` for deep links.** Set `server.publicBaseUrl` in `kibana.yml` so that `{{rule.url}}` and
   `{{kibanaBaseUrl}}` variables resolve to valid URLs in notifications.

9. **Tag rules consistently.** Use tags like `production`, `staging`, `team-platform` for filtering and organization in
   the Find API and UI.

10. **Use Kibana Spaces** to isolate rules by team or environment. Use a CLI context per space. Connectors are also
    space-scoped, so create matching connectors in each space.

## Common Pitfalls

1. **Wrong `consumer` value.** Using an invalid consumer (e.g., `observability` instead of `infrastructure`) causes a
   400 error. Check the rule type's supported consumers via `elastic kb alerting get-rule-types`.

2. **Immutable fields on update.** You cannot change `rule_type_id` or `consumer` with PUT. You must delete and recreate
   the rule.

3. **Read-only fields on update.** Sending GET output to PUT unfiltered returns 400; use the
   [update](#updating-a-rule) filter.

4. **Rule-level `notify_when` and `throttle` are deprecated.** Setting these at the rule level still works but conflicts
   with action-level frequency settings. Always use `frequency` inside each action object.

5. **Rule ID conflicts.** Creating with an existing ID returns 409. Check existence first with `get-alerting-rule-id`.

6. **API key ownership.** Rules run using the API key of the user who created or last updated them. If that user's
   permissions change or the user is deleted, the rule may fail silently. Use `post-alerting-rule-id-update-api-key` to
   re-associate.

7. **Too many actions per rule.** Rules generating thousands of alerts with multiple actions can clog Task Manager. The
   server setting `xpack.alerting.rules.run.actions.max` (default varies) limits actions per run. Design rules to use
   alert summaries or limit term sizes.

8. **Long-running rules.** Rules that run expensive queries are cancelled after `xpack.alerting.rules.run.timeout`
   (default `5m`). When cancelled, all alerts and actions from that run are discarded. Optimize queries or increase the
   timeout for specific rule types.

9. **Concurrent update conflicts.** PUT returns 409 if the rule was modified by another user since you last read it.
   Always GET the latest version before updating.

10. **Import/export loses secrets.** Rules exported via Saved Objects are disabled on import. Connectors lose their
    secrets and must be re-configured.

11. **`Pass --yes to confirm`.** Delete commands require `--yes`.

## Examples

**Create a threshold alert:** "Alert me when CPU exceeds 90% on any host for 5 minutes." Use
`rule_type_id: ".index-threshold"`, `aggField: "system.cpu.total.pct"`, `threshold: [0.9]`, and `timeWindowSize: 5`.
Attach a PagerDuty action on `"threshold met"` and a matching `Recovered` action to auto-close incidents.

**Find rules by tag:** "Show all production alerting rules."
`get-alerting-rules-find --filter 'alert.attributes.tags:"production"' --sort-field name`, paging with `--page`.

**Pause a rule temporarily:** "Disable rule abc123 until next Monday." `post-alerting-rule-id-disable --id abc123`.
Re-enable with `post-alerting-rule-id-enable` when ready; the rule retains all configuration while disabled. Or snooze it
until Monday with `post-alerting-rule-id-snooze-schedule`.

## Guidelines

- Set `frequency` inside each action object — rule-level `notify_when` and `throttle` are deprecated.
- `rule_type_id` and `consumer` are immutable after creation; delete and recreate the rule to change them.
- Use a CLI context whose `kibana.url` ends in `/s/<space_id>` for non-default Kibana Spaces.
- Always pair an active action with a `Recovered` action to auto-close PagerDuty, Jira, and ServiceNow incidents.
- Run `elastic kb alerting get-rule-types` first to discover valid `consumer` values and action group names.
- Use `alert_delay` to suppress transient spikes; use the `flapping` object to reduce noise from unstable conditions.

## Operations

Verified against CLI 0.7.0. All commands are under `elastic kb alerting` unless noted.

| HTTP API                                                         | CLI command                                                                        | Kibana                  |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ----------------------- |
| `GET /api/status`                                                | `elastic kb system get-status`                                                     | all                     |
| `POST /api/alerting/rule/{id}`                                   | `post-alerting-rule-id --id '<id>' --input-file rule.json`                         | all                     |
| `PUT /api/alerting/rule/{id}`                                    | `put-alerting-rule-id --id '<id>' --input-file rule.json`                          | all                     |
| `GET /api/alerting/rule/{id}`                                    | `get-alerting-rule-id --id '<id>'`                                                 | all                     |
| `DELETE /api/alerting/rule/{id}`                                 | `delete-alerting-rule-id --id '<id>' --yes`                                        | all                     |
| `GET /api/alerting/rules/_find`                                  | `get-alerting-rules-find [--search] [--filter] [--sort-field] [--page] [--per-page]` | all                   |
| `GET /api/alerting/rule_types`                                   | `get-rule-types`                                                                   | stack only\*            |
| `POST /api/alerting/rule/{id}/_enable`                           | `post-alerting-rule-id-enable --id '<id>'`                                         | all                     |
| `POST /api/alerting/rule/{id}/_disable`                          | `post-alerting-rule-id-disable --id '<id>' [--body '{"untrack":true}']`            | all                     |
| `POST /api/alerting/rule/{id}/_mute_all`                         | `post-alerting-rule-id-mute-all --id '<id>'`                                       | all                     |
| `POST /api/alerting/rule/{id}/_unmute_all`                       | `post-alerting-rule-id-unmute-all --id '<id>'`                                     | all                     |
| `POST /api/alerting/rule/{rule_id}/alert/{alert_id}/_mute`       | `post-alerting-rule-rule-id-alert-alert-id-mute --rule-id '<id>' --alert-id '<id>'`   | all                  |
| `POST /api/alerting/rule/{rule_id}/alert/{alert_id}/_unmute`     | `post-alerting-rule-rule-id-alert-alert-id-unmute --rule-id '<id>' --alert-id '<id>'` | all                  |
| `POST /api/alerting/rule/{id}/_update_api_key`                   | `post-alerting-rule-id-update-api-key --id '<id>'`                                 | all                     |
| `POST /api/alerting/rule/{id}/snooze_schedule`                   | `post-alerting-rule-id-snooze-schedule --id '<id>' --schedule '<json>'`            | 8.19+                   |
| `DELETE /api/alerting/rule/{ruleId}/snooze_schedule/{scheduleId}` | `delete-alerting-rule-ruleid-snooze-schedule-scheduleid --rule-id '<id>' --schedule-id '<id>' --yes` | 8.19+ |
| `GET /api/alerting/_health`                                      | `get-alerting-health`                                                              | stack only\*            |

\* CLI 0.7.0 hides these when the context targets Serverless. There, read rule-type params and action groups from an
existing rule (`get-alerting-rule-id`) or the [Kibana Alerting API Reference](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-alerting).

## Additional Resources

- [Kibana Alerting API Reference](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-alerting)
- [Alerting Concepts](https://www.elastic.co/docs/explore-analyze/alerting/alerts)
- [Create and Manage Rules (UI)](https://www.elastic.co/docs/explore-analyze/alerting/alerts/create-manage-rules)
- [Rule Action Variables](https://www.elastic.co/docs/explore-analyze/alerting/alerts/rule-action-variables)
- [Alerting Production Considerations](https://www.elastic.co/docs/deploy-manage/production-guidance/kibana-alerting-production-considerations)
- [Terraform: elasticstack_kibana_alerting_rule](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/kibana_alerting_rule)
- [Terraform: Managing Kibana Rule and Connector Resources](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/guides/elasticstack-kibana-rule)
