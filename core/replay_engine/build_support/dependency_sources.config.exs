project_root = Path.expand("..", __DIR__)
repo_root = Path.expand("../..", project_root)

%{
  deps: %{
    aitrace: %{
      path: repo_root,
      github: %{repo: "nshkrdotcom/AITrace", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    ai_trace_replay_contracts: %{
      path: Path.join(repo_root, "core/replay_contracts"),
      github: %{repo: "nshkrdotcom/AITrace", branch: "main", subdir: "core/replay_contracts"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
