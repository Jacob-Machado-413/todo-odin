package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/timezone"

Command :: enum {
	List,
	Add,
	Done,
	Remove,
	Config,
	Help,
	Invalid,
}

// Saved settings, stored as `key = value` lines at config_path().
Config :: struct {
	source: string, // backing todo file; "" means use the default
	json:   bool, // print all output as JSON
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

main :: proc() {

	command: Command = .List
	others: []string
	if len(os.args) > 1 {

		ok: bool
		command, ok = command_from_string(os.args[1])
		others = os.args[2:]

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
	case .Config:
		cmd_config(others)
	case .Done:
		cmd_done(others)
	case .Remove:
		cmd_rm(others)
	}


}

default_todo_path :: proc() -> string {
	home := os.get_env("HOME", context.allocator)
	path, _ := filepath.join({home, "todo.md"})
	return path
}

// $XDG_CONFIG_HOME/todo/config, falling back to ~/.config/todo/config.
config_path :: proc() -> string {
	dir := os.get_env("XDG_CONFIG_HOME", context.allocator)
	if dir == "" {
		dir, _ = filepath.join({os.get_env("HOME", context.allocator), ".config"})
	}
	path, _ := filepath.join({dir, "todo", "config"})
	return path
}

// TODO_FILE env var > config file > ~/todo.md
get_todo_path :: proc() -> string {
	if path := os.get_env("TODO_FILE", context.allocator); path != "" {
		return path
	}
	if cfg := load_config(); cfg.source != "" do return cfg.source
	return default_todo_path()
}

// Missing file -> all defaults. Blank lines, `#` comments and unknown keys
// are ignored.
load_config :: proc() -> (cfg: Config) {
	data, err := os.read_entire_file(config_path(), context.allocator)
	if err != nil do return

	src := string(data)
	for line in strings.split_lines_iterator(&src) {
		line := strings.trim_space(line)
		if line == "" || line[0] == '#' do continue
		eq := strings.index_byte(line, '=')
		if eq < 0 do continue

		key := strings.trim_space(line[:eq])
		value := strings.trim_space(line[eq + 1:])
		switch key {
		case "source":
			cfg.source = value
		case "json":
			cfg.json = value == "on"
		}
	}
	return
}

save_config :: proc(cfg: Config) {
	sb := strings.builder_make()
	if cfg.source != "" do fmt.sbprintfln(&sb, "source = %s", cfg.source)
	fmt.sbprintfln(&sb, "json = %s", cfg.json ? "on" : "off")

	path := config_path()
	ensure_todo_dir(path)
	if err := os.write_entire_file(path, strings.to_string(sb)); err != nil {
		fmt.eprintfln("could not write config %s: %v", path, err)
		os.exit(1)
	}
}

ensure_todo_dir :: proc(path: string) {
	dir := filepath.dir(path)
	os.make_directory_all(dir)
}

CONFIG_USAGE :: "usage: todo config [source [path] | json [on|off]]"

// `todo config`               -> print all settings
// `todo config source [path]` -> print / set the backing file
// `todo config json [on|off]` -> print / set JSON output
cmd_config :: proc(args: []string) {
	cfg := load_config()
	if len(args) == 0 {
		if cfg.json {
			print_json(struct {
				source: string `json:"source"`,
				json:   bool `json:"json"`,
			}{get_todo_path(), true})
		} else {
			fmt.printfln("source = %s", get_todo_path())
			fmt.println("json = off")
		}
		return
	}

	switch args[0] {
	case "source":
		config_source(&cfg, args[1:])
	case "json":
		config_json(&cfg, args[1:])
	case:
		fmt.eprintln(CONFIG_USAGE)
		os.exit(1)
	}
}

config_json :: proc(cfg: ^Config, args: []string) {
	if len(args) == 0 {
		if cfg.json do print_json(true)
		else do fmt.println("off")
		return
	}
	switch args[0] {
	case "on":
		cfg.json = true
	case "off":
		cfg.json = false
	case:
		fmt.eprintln(CONFIG_USAGE)
		os.exit(1)
	}
	save_config(cfg^)
	if cfg.json do print_json(true)
	else do fmt.println("json output off")
}

config_source :: proc(cfg: ^Config, args: []string) {
	if len(args) == 0 {
		if cfg.json do print_json(get_todo_path())
		else do fmt.println(get_todo_path())
		return
	}

	// not os.get_absolute_path: that uses realpath, which fails if the file
	// doesn't exist yet
	path := args[0]
	if !filepath.is_abs(path) {
		wd, err := os.get_working_directory(context.allocator)
		if err != nil {
			fmt.eprintfln("could not get working directory: %v", err)
			os.exit(1)
		}
		path, _ = filepath.join({wd, path})
	}

	cfg.source = path
	save_config(cfg^)
	if cfg.json do print_json(path)
	else do fmt.printfln("todo file set to %s", path)

	if os.get_env("TODO_FILE", context.allocator) != "" {
		fmt.eprintln("note: TODO_FILE is set and overrides this")
	}
}

ensure_file_exist :: proc(path:string){

}


// `todo add (A) call bob +work due:2026-10-10`
cmd_add :: proc(args: []string) {
	text := strings.join(args, " ")
	if _, ok := new_description(text); !ok {
		fmt.eprintln("todo can't contain newlines")
		os.exit(1)
	}

	item, ok := parse_todo(strings.concatenate({"- [ ] ", text}))
	if !ok {
		fmt.eprintln("usage: todo add [(A)] [created-date] description [+project] [@context] [due:YYYY-MM-DD]")
		os.exit(1)
	}
	if item.created == nil do item.created = local_today()

	path := get_todo_path()
	ensure_todo_dir(path)

	// if the file doesn't end in a newline (e.g. last edited in obsidian),
	// add one so the new todo doesn't get glued onto the last line
	line := strings.concatenate({todo_to_string(item), "\n"})
	existing, _ := os.read_entire_file(path, context.allocator)
	if len(existing) > 0 && existing[len(existing) - 1] != '\n' {
		line = strings.concatenate({"\n", line})
	}

	f, err := os.open(path, {.Write, .Append, .Create})
	if err != nil {
		fmt.eprintfln("could not open %s: %v", path, err)
		os.exit(1)
	}
	defer os.close(f)
	if _, werr := os.write_string(f, line); werr != nil {
		fmt.eprintfln("could not write to %s: %v", path, werr)
		os.exit(1)
	}
	if load_config().json {
		// the new todo is last, so its index is one past the existing ones
		print_json(todo_to_json(item, len(parse_todos(string(existing))) + 1))
	} else {
		fmt.print(strings.trim_left(line, "\n"))
	}
}

// Today's date in the local timezone, as midnight UTC - the same shape
// parse_date produces. Falls back to the UTC date if the zone can't be loaded.
local_today :: proc() -> time.Time {
	now, _ := time.time_to_datetime(time.now())
	if tz, ok := timezone.region_load("local"); ok && tz != nil {
		defer timezone.region_destroy(tz)
		if local, lok := timezone.datetime_to_tz(now, tz); lok do now = local
	}
	today, _ := time.components_to_time(now.year, now.month, now.day, 0, 0, 0)
	return today
}


// All todo lines in `data`, in file order. Lines that aren't todos (headings,
// notes added in obsidian) are skipped, so a todo's index is its position in
// this list, not its line number. Items slice into `data`; keep it alive.
parse_todos :: proc(data: string) -> [dynamic]Todo_Line {
	todos := make([dynamic]Todo_Line)
	start := 0
	for start < len(data) {
		nl := strings.index_byte(data[start:], '\n')
		next := nl < 0 ? len(data) : start + nl + 1
		end := nl < 0 ? len(data) : start + nl
		if end > start && data[end - 1] == '\r' do end -= 1

		if item, ok := parse_todo(data[start:end]); ok {
			append(&todos, Todo_Line{item, start, end, next})
		}
		start = next
	}
	return todos
}

// A parsed todo plus where it sits in the file: data[start:end] is the line
// without its line ending, data[next:] is everything after it.
Todo_Line :: struct {
	item:              TodoItem,
	start, end, next: int,
}

// `todo list` -> every todo, numbered from 1
cmd_list :: proc(args: []string) {
	path := get_todo_path()

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil && err != .Not_Exist {
		fmt.eprintfln("could not read %s: %v", path, err)
		os.exit(1)
	}
	todos := parse_todos(string(data)) // missing file -> no todos

	if load_config().json {
		rows := make([]Todo_Json, len(todos))
		for t, i in todos do rows[i] = todo_to_json(t.item, i + 1)
		print_json(rows)
		return
	}

	for t, i in todos do print_todo(t.item, i + 1)
}

// One todo as a line of `list` text output.
print_todo :: proc(item: TodoItem, index: int) {
	buf: [len("2026-09-17")]u8
	fmt.printf("% 3d [%c] ", index, item.completed ? 'x' : ' ') // "% 3d": plain %3d zero-pads
	if p, ok := item.priority.?; ok do fmt.printf("(%c) ", 'A' + rune(p))
	fmt.print(item.description)
	if d, ok := item.due_date.?; ok do fmt.printf("  due %s", time.to_string_yyyy_mm_dd(d, buf[:]))
	fmt.println()
}

// `todo done 1 3` -> mark todos 1 and 3 completed, stamped with today's date
// `todo rm 2`     -> delete todo 2
// Indexes are the ones `list` prints. All are checked before anything is
// written; non-todo lines and untouched todos are kept byte-for-byte.
cmd_done :: proc(args: []string) {edit_todos(args, remove = false)}
cmd_rm :: proc(args: []string) {edit_todos(args, remove = true)}

edit_todos :: proc(args: []string, remove: bool) {
	usage := remove ? "usage: todo rm <index>..." : "usage: todo done <index>..."
	if len(args) == 0 {
		fmt.eprintln(usage)
		os.exit(1)
	}

	path := get_todo_path()
	raw, err := os.read_entire_file(path, context.allocator)
	if err != nil && err != .Not_Exist {
		fmt.eprintfln("could not read %s: %v", path, err)
		os.exit(1)
	}
	data := string(raw)
	todos := parse_todos(data)

	selected := make([]bool, len(todos))
	for arg in args {
		n, ok := strconv.parse_int(arg)
		if !ok {
			fmt.eprintln(usage)
			os.exit(1)
		}
		if n < 1 || n > len(todos) {
			fmt.eprintfln("no todo %d (there are %d)", n, len(todos))
			os.exit(1)
		}
		selected[n - 1] = true
	}

	today := local_today()
	changed := make([dynamic]Todo_Json)
	sb := strings.builder_make()
	cursor := 0
	for &t, i in todos {
		if !selected[i] do continue
		strings.write_string(&sb, data[cursor:t.start])

		if remove {
			cursor = t.next
		} else {
			if !t.item.completed {
				t.item.completed = true
				// completion is only written alongside a created date, see
				// todo_to_string; without one the todo is just checked off
				if t.item.created != nil do t.item.completion = today
			}
			strings.write_string(&sb, todo_to_string(t.item))
			cursor = t.end
		}
		append(&changed, todo_to_json(t.item, i + 1))
	}
	strings.write_string(&sb, data[cursor:])

	// write to a temp file and rename over the original, so a crash
	// mid-write can't leave a half-written todo file
	tmp := strings.concatenate({path, ".tmp"})
	if werr := os.write_entire_file(tmp, strings.to_string(sb)); werr != nil {
		fmt.eprintfln("could not write %s: %v", tmp, werr)
		os.exit(1)
	}
	if rerr := os.rename(tmp, path); rerr != nil {
		fmt.eprintfln("could not replace %s: %v", path, rerr)
		os.exit(1)
	}

	if load_config().json {
		print_json(changed[:])
		return
	}
	for t, i in todos {
		if !selected[i] do continue
		fmt.print(remove ? "removed " : "done    ")
		print_todo(t.item, i + 1)
	}
}

// ---------------------------------------------------------------------------
// json output
// ---------------------------------------------------------------------------

// What a todo looks like in JSON. Dates are "YYYY-MM-DD" strings; unset
// fields are null so every row has the same columns.
Todo_Json :: struct {
	index:       int `json:"index"`,
	done:        bool `json:"done"`,
	priority:    Maybe(string) `json:"priority"`,
	created:     Maybe(string) `json:"created"`,
	completion:  Maybe(string) `json:"completion"`,
	due:         Maybe(string) `json:"due"`,
	description: string `json:"description"`,
	projects:    []string `json:"projects"`,
	contexts:    []string `json:"contexts"`,
}

todo_to_json :: proc(item: TodoItem, index: int) -> Todo_Json {
	date_string :: proc(t: Maybe(time.Time)) -> Maybe(string) {
		d, ok := t.?
		if !ok do return nil
		buf: [len("2026-09-17")]u8
		return strings.clone(time.to_string_yyyy_mm_dd(d, buf[:]))
	}

	out := Todo_Json {
		index       = index,
		done        = item.completed,
		created     = date_string(item.created),
		completion  = date_string(item.completion),
		due         = date_string(item.due_date),
		description = item.description,
		projects    = item.projects,
		contexts    = item.contexts,
	}
	if p, ok := item.priority.?; ok {
		out.priority = fmt.aprintf("%c", 'A' + rune(p))
	}
	return out
}

print_json :: proc(v: any) {
	data, err := json.marshal(v)
	if err != nil {
		fmt.eprintfln("could not encode json: %v", err)
		os.exit(1)
	}
	fmt.println(string(data))
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
	case "config":
		return .Config, true
	case:
		return .List, false
	}
}
Description :: distinct string

TodoItem :: struct {
	priority:    Maybe(Priority),
	completion:  Maybe(time.Time), // only written when completed and created is set
	created:     Maybe(time.Time),
	due_date:    Maybe(time.Time),
	description: string,
	projects:    []string,
	contexts:    []string,
	completed:   bool,
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
	if created, ok := item.created.?; ok {
		// a lone date reads back as created, so completion needs created after it
		if completion, cok := item.completion.?; cok && item.completed {
			strings.write_string(&sb, time.to_string_yyyy_mm_dd(completion, buf[:]))
			strings.write_byte(&sb, ' ')
		}
		strings.write_string(&sb, time.to_string_yyyy_mm_dd(created, buf[:]))
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

