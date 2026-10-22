class_name PlaybookStore
extends RefCounted
## Saves the user's playbooks to disk, one .tres file per playbook, with offensive and
## defensive playbooks in separate folders. user:// is the per-user data folder on desktop
## and browser storage on the web export.

## Where the playbooks live. Tests point this somewhere else so they don't touch the user's.
static var root := "user://playbooks"


static func dir_for(kind: String) -> String:
	return "%s/%s" % [root, kind]


## Every saved playbook of this kind (Playbook.OFFENSE or Playbook.DEFENSE), oldest first.
static func list(kind: String) -> Array[Playbook]:
	var out: Array[Playbook] = []
	var dir := dir_for(kind)
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var pb := ResourceLoader.load("%s/%s" % [dir, f]) as Playbook
		if pb == null:
			push_warning("Couldn't load playbook %s/%s" % [dir, f])
			continue
		pb.link_plays()
		out.append(pb)
	return out


## A new playbook of this kind, named "Offensive Playbook #N" (or Defensive), with the stock
## packages in it. Saved straight away.
static func create(kind: String) -> Playbook:
	var existing := list(kind)
	var taken := {}
	for pb in existing:
		taken[pb.name] = true
	var label := "Offensive" if kind == Playbook.OFFENSE else "Defensive"
	var n := existing.size() + 1
	while taken.has("%s Playbook #%d" % [label, n]):
		n += 1
	var name := "%s Playbook #%d" % [label, n]
	var pb := Playbook.make_offense(name) if kind == Playbook.OFFENSE else Playbook.make_defense(name)
	save(pb)
	return pb


## Writes the playbook back to its file, giving it one first if it's new.
static func save(pb: Playbook) -> Error:
	var dir := dir_for(pb.kind)
	if pb.resource_path == "":
		DirAccess.make_dir_recursive_absolute(dir)
		pb.take_over_path("%s/playbook_%04d.tres" % [dir, _next_number(dir)])
	var err := ResourceSaver.save(pb)
	if err != OK:
		push_error("Couldn't save playbook %s: %s" % [pb.name, error_string(err)])
	return err


## One more than the highest numbered file in the folder, so files sort in creation order.
static func _next_number(dir: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("playbook_") and f.ends_with(".tres"):
			n = maxi(n, f.trim_prefix("playbook_").trim_suffix(".tres").to_int())
	return n + 1


static func delete(pb: Playbook) -> void:
	if pb.resource_path != "":
		DirAccess.remove_absolute(pb.resource_path)
