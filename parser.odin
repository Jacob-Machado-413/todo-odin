package main

import "core:strconv"
import "core:strings"
import "core:time"
// ---------------------------------------------------------------------------
// parsing
// ---------------------------------------------------------------------------

// A cursor over the input. `rest` is everything not yet consumed; every helper

Parser :: struct {
	rest: string,
}

Parse_Error :: enum {
	None = 0, // zero value, so `err != nil` and `or_return` work
	Not_A_Todo, // no "- [ ]" mark; caller skips the line
	Bad_Mark,
	Bad_Date,
	Bad_Priority,
	Empty_Description,
}

// Drop a leading run of spaces/tabs.
p_skip_space :: proc(p: ^Parser) {
	p.rest = strings.trim_left_space(p.rest)
}

// If `rest` starts with `prefix`, consume it and report true. Otherwise the
// parser is left untouched - this is the "try to match" primitive.
p_eat :: proc(p: ^Parser, prefix: string) -> bool {
	if !strings.has_prefix(p.rest, prefix) do return false
	p.rest = p.rest[len(prefix):]
	return true
}

// Next whitespace-delimited word, consumed. "" when the input is exhausted.
p_next_word :: proc(p: ^Parser) -> string {
	p_skip_space(p)
	if p.rest == "" do return ""
	i := strings.index_any(p.rest, " \t")
	if i < 0 {
		w := p.rest
		p.rest = ""
		return w
	}
	w := p.rest[:i]
	p.rest = p.rest[i:]
	return w
}

// Look at the next word without committing to it: copy the cursor, advance the
// copy, throw it away. This is how you get lookahead without a pushback buffer.
p_peek_word :: proc(p: ^Parser) -> string {
	q := p^
	return p_next_word(&q)
}

// "2026-09-17" -> time.Time. ok=false for anything that isn't exactly that shape.
parse_date :: proc(s: string) -> (t: time.Time, err: Parse_Error) {

	if len(s) != len("2009-04-13") || s[4] != '-' || s[7] != '-' {
		return {}, .Bad_Date
	}


	y, y_ok := strconv.parse_int(s[0:4])
	m, m_ok := strconv.parse_int(s[5:7])
	d, d_ok := strconv.parse_int(s[8:10])
	if !y_ok || !m_ok || !d_ok {
		return {}, .Bad_Date
	}

	res, ok := time.components_to_time(y, m, d, 0, 0, 0)
	return res, .None if ok else .Bad_Date

}


//   - [ ] (A) 2026-09-16 2026-09-17 walk the dog +home @errands due:2026-09-18
//   ^^^^^ ^^^ ^^^^^^^^^^ ^^^^^^^^^^ ^^^^^^^^^^^^ ^^^^^ ^^^^^^^^ ^^^^^^^^^^^^^
//   mark  prio completion created   description  proj  context  due
//
// Only the mark + description are mandatory.
parse_todo :: proc(s: string, allocator := context.allocator) -> (item: TodoItem, ok: bool) {
	p := Parser{strings.trim_space(s)}

	
	//completed status
	if !p_eat(&p, "- [") || len(p.rest) == 0 do return {}, false
	status := p.rest[0]
	if status == 'x' || status == 'X' {
		item.completed = true
	} 
	else if status == ' ' {
		item.completed =false
	}
	else {
		return {}, false 
	}
	p.rest = p.rest[1:]
	if !p_eat(&p, "]") do return {}, false


	// 2. priority "(A)" - optional, so peek before committing.
	w := p_peek_word(&p)
	if len(w) == 3 && w[0] == '(' && w[2] == ')' {
		if prio, pok := priority_from_rune(rune(w[1])); pok {
			item.priority = prio   
	        p_next_word(&p)
	        }
		}

	// 3. dates
	{
		q := p
		completion, c_err := parse_date(p_next_word(&q))
		created, cr_err := parse_date(p_next_word(&q))
		if c_err == nil && cr_err == nil {
			dates: type_of(item.dates.?)
			dates.completion = completion
			dates.created = created
			item.dates = dates
			p = q
		}
	}


	// 4. description + tags.
	//    +proj / @ctx are legal anywhere and stay in the description text;
	p_skip_space(&p)
	start := p.rest
	desc_end := len(start)

	projects := make([dynamic]string, 0, 4, allocator)
	contexts := make([dynamic]string, 0, 4, allocator)

	for {
		w := p_next_word(&p)
		if w == "" do break

		switch {
		case len(w) > 1 && w[0] == '+':
			append(&projects, w[1:])
		case len(w) > 1 && w[0] == '@':
			append(&contexts, w[1:])
		case strings.has_prefix(w, "due:") && p_peek_word(&p) == "":
			if d, err := parse_date(w[4:]); err == nil {
				item.due_date = d
				desc_end = len(start) - len(p.rest) - len(w)
			}
		}
	}

	item.description = strings.trim_space(start[:desc_end])
	if item.description == "" {
		delete(projects)
		delete(contexts)
		return {}, false
	}

	item.projects = projects[:] // dynamic array -> slice; caller frees with delete()
	item.contexts = contexts[:]

	return item, true
}

priority_from_rune :: proc(r: rune) -> (Priority, bool) {
	if r < 'A' || r > 'Z' do return .A, false
	return Priority(r - 'A'), true
}
