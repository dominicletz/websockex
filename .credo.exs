# .credo.exs
%{
  configs: [
    %{
      name: "default",
      checks: %{
        disabled: [
          # this means that `TabsOrSpaces` will not run
          {Credo.Check.Warning.SpecWithStruct, []},
        ]
      }
      # files etc.
    }
  ]
}
