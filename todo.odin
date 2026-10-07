package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

main :: proc() {

	command: Command = .List
	others: []string
	if len(os.args) > 1 {

		command, ok := command_from_string(os.args[1])
		others := os.args[2:]

		if !ok {
			fmt.eprintfln("unknown command: %s", os.args[1])
			os.exit(1)
		}
	}

	#partial switch command {
	case .List:
		cmd_list(others)
	case .Add:
		cmd_add(others)
	}


}

default_todo_path :: proc() -> string {
	home := os.get_env("HOME", context.allocator)
	path, _ := filepath.join({home, "todo.md"})
	return path
}

get_todo_path :: proc() -> string {
	if path := os.get_env("TODO_FILE", context.allocator); path != "" {
		return path
	}
	return default_todo_path()
}

ensure_todo_dir :: proc(path: string) {
	dir := filepath.dir(path)
	os.make_directory(dir)
}

ensure_file_exist :: proc(path:string){

}


cmd_add :: proc(args: []string) {
	//in case of add, rest of string is one description.
	fmt.println("werkin on it Add")
}


//list all current todos
cmd_list :: proc(args: []string) {
	path := get_todo_path()

    f, err := os.read_entire_file(path, context.allocator)


    if err != nil{
        
        if err == .Not_Exist{
            //no todo file yet: make the containing dir and start an empty one
            ensure_todo_dir(path)
            if werr := os.write_entire_file(path, ""); werr != nil {
                fmt.eprintfln("Error creating todo file at %s", path)
                fmt.eprintfln("%v", werr)
                os.exit(1)
            } else{
                //TODO: DONT SEND IT
                //send it
                f, _ = os.read_entire_file(path, context.allocator)
            }
        } else{
            //flip the fuck out
            fmt.printfln("Error with file read")
            fmt.printfln("%v", err)
            os.exit(1)
        }
    }

    src:= string(f) //alias not copy

    for line in strings.split_lines_iterator(&src){
        trimmed := strings.trim_space(line);
        if trimmed == "" do continue

        
    }


    //split into rows
    //for line in lines parse_todo() into []TodoItems 
    // ???
    //output string data

    

    
    


}


command_from_string :: proc(s: string) -> (Command, bool) {
	switch s {
	case "list":
		return .List, true
	case "add":
		return .Add, true
	case "done":
		return .Done, true
	case "rm":
		return .Remove, true
	case "help":
		return .Help, true
	case "source":
		return .ChangeSource, true
	case:
		return .List, false
	}
}
Command :: enum {
	List,
	Add,
	Done,
	Remove,
	ChangeSource,
	Help,
	Invalid,
}


Description :: distinct string

TodoItem :: struct {
	priority:    Maybe(Priority),
	dates:       Maybe(struct {
			completion: time.Time,
			created:    time.Time,
		}),
	due_date:    Maybe(time.Time),
	description: string,
	projects:    []string,
	contexts:    []string,
	completed:   bool,
}

Priority :: enum u8 {
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
}

new_description :: proc(s: string) -> (Description, bool) {
	if strings.contains_any(s, "\n\r") do return "", false


	return Description(s), true
}

//not for output, but for the .md storage
todo_to_string :: proc(item: TodoItem) -> string {
	//"- [ ] (12) 2026-09-16 2026-09-17 descriptionblahblah +project1 +project2 @context1 @context2 due:2026-09-18"

	buf: [len("2026-09-17")]u8 //god willing nobody is using this in the year 10000

	sb := strings.builder_make()
	strings.write_string(&sb, "- [")
	strings.write_string(&sb, item.completed ? "X] " : " ] ")
	if p, ok := item.priority.?; ok {
		strings.write_rune(&sb, '(')
		strings.write_rune(&sb, 'A' + rune(p))
		strings.write_string(&sb, ") ")
	}
	if d, ok := item.dates.?; ok {

		strings.write_string(&sb, time.to_string_yyyy_mm_dd(d.completion, buf[:]))
		strings.write_byte(&sb, ' ')
		strings.write_string(&sb, time.to_string_yyyy_mm_dd(d.created, buf[:]))
		strings.write_byte(&sb, ' ')
	}
	// projects/contexts live inside the description, so they're not written again
	strings.write_string(&sb, item.description)

	if d, ok := item.due_date.?; ok {
		strings.write_byte(&sb, ' ')
		strings.write_string(&sb, "due:")
		strings.write_string(&sb, time.to_string_yyyy_mm_dd(d, buf[:]))

	}

	return strings.to_string(sb)
}

