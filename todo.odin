package main

import "core:fmt"
import "core:os"
import "core:time"

main::proc(){

    command: Command = .List;
    if len(os.args) > 1{

        command, ok := command_from_string(os.args[1])
        others := os.args[2:]

        if !ok {
            fmt.eprintfln("unknown command: %s", os.args[1])
            os.exit(1)
        }
    }


}



command_from_string :: proc(s: string) -> (Command, bool) {
    switch s {
    case "list":  return .List, true
    case "add":   return .Add, true
    case "done":  return .Done, true
    case "rm":    return .Remove, true
    case "help":  return .Help, true
    case "source":return .ChangeSource, true 
    case:        return .List, false  
    }
}
Command::enum{
    List,
    Add,
    Done,
    Remove,
    ChangeSource,
    Help,
    Invalid
}


TodoItem :: struct{
    priority: int,
    completionDate: time.Time,
    creationDate: time.Time,
    dueDate: Maybe(time.Time),
    description: string,
    projects: []string,
    contexts: []string,
    completion: bool,
}
