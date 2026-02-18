# Phase 4: LiveView UI & Slack Integration

## Overview

This plan covers two major features that share a common foundation:

1. **Phase A: LiveView UI** - Web interface for managing deployments with user authentication
2. **Phase B: Slack Integration** - Slash commands and rich Block Kit messages for deployment management

Both features require a **shared deployment state layer** that tracks deployments in real-time and broadcasts progress events. This shared infrastructure must be built first.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                     Entry Points                                 │
├─────────────────┬───────────────────┬───────────────────────────┤
│   LiveView UI   │   Slack Commands  │        CLI (existing)     │
│  (Phoenix app)  │  (Plug endpoint)  │      (mix deploy)         │
└────────┬────────┴─────────┬─────────┴─────────────┬─────────────┘
         │                  │                       │
         ▼                  ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│              Deploy.Deployments (Shared State Layer)            │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   Registry   │  │   Events     │  │   Supervisor           │ │
│  │  (GenServer) │  │   (PubSub)   │  │   (DynamicSupervisor)  │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Reactor Layer (existing)                           │
│         Setup → MergePRs → DeployPR (with middleware)           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Shared Foundation (Build First)

Before either UI or Slack, we need:

### 1. Database Layer
- **Users table**: username, password_hash, display_name, active
- **Deployments table**: id, user_id, deploy_date, pr_numbers, status, current_phase, current_step, error_message, reactor_state, timestamps
- **Deployment steps table**: deployment_id, phase, step_name, status, started_at, completed_at, result, error
- **Merged PRs table**: deployment_id, pr_number, pr_title, merge_sha

### 2. Deployment State Layer
- `Deploy.Deployments.Registry` - GenServer tracking active/recent deployments
- `Deploy.Deployments.Events` - PubSub for broadcasting progress
- `Deploy.Deployments.Supervisor` - DynamicSupervisor for runner processes
- `Deploy.Deployments.Runner` - GenServer managing a single deployment execution

### 3. Reactor Middleware
- `Deploy.Reactors.Middleware.EventBroadcaster` - broadcasts step start/complete/fail events to PubSub
- Enables LiveView and Slack to receive real-time updates without modifying existing step code

---

## Phase A: LiveView UI

### Dependencies to Add
```elixir
{:phoenix, "~> 1.7"},
{:phoenix_live_view, "~> 0.20"},
{:phoenix_html, "~> 4.0"},
{:phoenix_live_reload, "~> 1.4", only: :dev},
{:ecto_sql, "~> 3.10"},
{:ecto_sqlite3, "~> 0.12"},  # SQLite - simple single-file DB
{:bcrypt_elixir, "~> 3.0"},
{:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
{:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
```

### Routes
```
GET  /login                    SessionController :new
POST /login                    SessionController :create
DELETE /logout                 SessionController :delete

# Authenticated routes
GET  /                         DashboardLive :index
GET  /deployments              DeploymentListLive :index
GET  /deployments/new          DeploymentNewLive :new
GET  /deployments/:id          DeploymentShowLive :show
```

### Key LiveViews

**Dashboard** (`/`)
- Summary of recent deployments
- Quick-start form
- Active deployment status

**Deployment List** (`/deployments`)
- Paginated history
- Filter by status/date
- Quick actions

**New Deployment** (`/deployments/new`)
- PR number input
- Reviewer selection
- Validation options
- Start button

**Deployment Show** (`/deployments/:id`) - **Real-time**
- Phase progress indicators (Setup → Merge → Create PR)
- Step-by-step progress within phases
- Live updates via PubSub subscription
- Resume/Cancel buttons for failed deployments
- Deploy PR link when complete

### Authentication
- Session-based (simple, no tokens)
- `mix deploy.user create <username> --password <password>`
- `mix deploy.user list`
- `mix deploy.user deactivate <username>`

---

## Phase B: Slack Integration

### Slack App Configuration Required
```
Slash Commands:
  /deploy [pr_numbers] [--skip-validation]
  /deploy-status
  /deploy-resume [deployment_id]

Bot Token Scopes:
  - chat:write
  - chat:write.public
  - commands

Interactivity Request URL: https://your-domain/api/slack/interactions
Slash Command URL: https://your-domain/api/slack/commands
```

### Dependencies to Add
```elixir
{:plug_cowboy, "~> 2.6"},  # If not using Phoenix endpoint
# Req already available for HTTP client
```

### Environment Variables
```
SLACK_BOT_TOKEN      # xoxb-... token for API calls
SLACK_SIGNING_SECRET # For verifying incoming requests
```

### Key Modules

**Deploy.Slack.Client**
- `post_message/3` - Post to channel, returns `{:ok, %{ts: ts}}`
- `update_message/4` - Update in-place using timestamp
- `respond/2` - Respond to slash command via response_url

**Deploy.Slack.Blocks**
- `deployment_status/1` - Build Block Kit message from deployment state
- Progress indicators with emojis
- PR list with merge status
- Action buttons (Resume, Cancel, View PR)

**Deploy.Slack.CommandParser**
- Parse `/deploy 12 13 --skip-validation` into structured opts

**Deploy.Web.SlackController**
- Handle slash commands (respond within 3s, run async)
- Handle button interactions
- Verify request signatures

**Deploy.Slack.Notifier**
- GenServer subscribing to deployment events
- Updates Slack message in-place as deployment progresses

### Message Update Strategy
1. Slash command → Acknowledge immediately (200 response)
2. Post initial status message to channel → Get `ts` (timestamp)
3. As deployment progresses → `chat.update` with same `ts` to modify message in-place
4. Store `{channel_id, message_ts}` in deployment state

### Block Kit Example (Failed Deployment)
```
┌─────────────────────────────────────────────────┐
│ :x: Deploy 20260218                             │
├─────────────────────────────────────────────────┤
│ :white_check_mark: Setup                        │
│ :x: Merge PRs - Failed                          │
│ :white_circle: Create PR                        │
├─────────────────────────────────────────────────┤
│ Error:                                          │
│ ```PR #13 has merge conflicts```                │
├─────────────────────────────────────────────────┤
│ [Resume Deployment] [Cancel]                    │
└─────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 0: Shared Foundation (Required for both UI and Slack)
1. Add Ecto + SQLite, set up database migrations
2. Create deployment schemas (Deployment, DeploymentStep, MergedPR)
3. Create `Deploy.Deployments` context module
4. Create `Deploy.Deployments.Registry` GenServer
5. Create `Deploy.Deployments.Events` PubSub
6. Create `Deploy.Deployments.Supervisor` DynamicSupervisor
7. Create `Deploy.Deployments.Runner` GenServer
8. Create `Deploy.Reactors.Middleware.EventBroadcaster`
9. Modify `Deploy.Runner` to use new state layer
10. Create Application supervisor

### Phase A: LiveView UI (Implement First)
1. Add Phoenix dependencies, generate boilerplate
2. Create User schema and `Deploy.Accounts` context
3. Create `mix deploy.user` task for user management
4. Implement session-based auth (login/logout)
5. Create DashboardLive (recent deployments, quick start)
6. Create DeploymentListLive (history, filtering)
7. Create DeploymentNewLive (form to start deployment)
8. Create DeploymentShowLive (real-time progress via PubSub)
9. Add resume/cancel functionality for failed deployments

### Phase B: Slack Integration (Implement After UI)
1. Add Slack config to `Deploy.Config` (bot token, signing secret)
2. Create `Deploy.Slack.Client` HTTP module
3. Create `Deploy.Slack.Blocks` message builder
4. Create `Deploy.Slack.CommandParser`
5. Create Slack App in workspace (slash commands, interactivity URL)
6. Create `SlackController` for commands and interactions
7. Create `Deploy.Slack.Notifier` event subscriber
8. Test with ngrok tunnel to local dev
9. Add request signature verification

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `mix.exs` | Add Phoenix, Ecto, bcrypt, plug_cowboy deps |
| `lib/config.ex` | Add Slack token/secret config functions |
| `lib/runner.ex` | Integrate with deployment state layer |
| `lib/deploy/application.ex` | Add supervision tree |

## New File Structure

```
lib/
├── deploy/
│   ├── accounts/
│   │   ├── user.ex
│   │   └── accounts.ex
│   ├── deployments/
│   │   ├── deployment.ex
│   │   ├── deployment_step.ex
│   │   ├── merged_pr.ex
│   │   ├── deployments.ex
│   │   ├── registry.ex
│   │   ├── supervisor.ex
│   │   ├── runner.ex
│   │   └── events.ex
│   ├── slack/
│   │   ├── client.ex
│   │   ├── blocks.ex
│   │   ├── command_parser.ex
│   │   └── notifier.ex
│   ├── repo.ex
│   └── application.ex
├── deploy_web/
│   ├── components/
│   ├── live/
│   │   ├── dashboard_live.ex
│   │   ├── deployment_list_live.ex
│   │   ├── deployment_new_live.ex
│   │   └── deployment_show_live.ex
│   ├── controllers/
│   │   ├── session_controller.ex
│   │   └── slack_controller.ex
│   ├── router.ex
│   └── endpoint.ex
└── mix/tasks/
    └── deploy.user.ex
```

---

## Decisions Made

- **Database**: SQLite (simple single-file, no server needed)
- **Phase order**: LiveView UI first, then Slack integration
- **Slack App**: Will be created during development (user has prior experience)
- **Hosting**: Local dev with ngrok initially, production hosting TBD

---

## Verification Plan

### Phase 0 Verification
- Unit tests for Registry, Events, Runner
- Integration test: deployment creates records, broadcasts events

### Phase A Verification
- Create user via mix task, log in via browser
- Start deployment, watch progress update in real-time
- Resume failed deployment

### Phase B Verification
- `/deploy 123` starts deployment, posts status message
- Message updates in-place as deployment progresses
- Resume button works on failed deployment
