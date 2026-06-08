# frozen_string_literal: true

module ShipChecks
  module HasPcbFiles
    DEFINITION = { key: :has_pcb_files, label: "PCB source files in repository", deps: [ :repo_tree ], visibility: :user }.freeze

    def self.call(ctx)
      tree = ctx.repo_tree
      if tree.nil?
        msg = ctx.non_github_repo? ? "Skipped (non-GitHub repository)" : "Repository not accessible"
        return ShipCheckService::CheckResult.new(
          key: "has_pcb_files", label: DEFINITION[:label],
          status: :skipped, message: msg, visibility: :user
        )
      end

      extensions = tree.map { |p| File.extname(p).downcase }
      has_kicad = %w[.kicad_pro .kicad_sch .kicad_pcb].all? { |ext| extensions.include?(ext) }
      has_easyeda = extensions.include?(".epro") || extensions.include?(".epro2")
      passed = has_kicad || has_easyeda
      ShipCheckService::CheckResult.new(
        key: "has_pcb_files",
        label: DEFINITION[:label],
        status: passed ? :passed : :warn,
        message: passed ? nil : "Add PCB source files (.kicad_pro/.kicad_sch/.kicad_pcb or .epro) if your project has a PCB",
        visibility: :user
      )
    end
  end
end
