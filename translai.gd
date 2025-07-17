@tool
extends EditorPlugin

# UI elements
var dock
var window: Window
var toolbar_button: Button
var loc_file_input: LineEdit
var language_option: OptionButton
var source_language_option: OptionButton
var tone_input: LineEdit
var character_id_input: LineEdit
var scan_button: Button
var translate_button: Button
var translate_all_button: Button
var add_row_button: Button
var save_button: Button
var add_language_button: Button
var add_language_selector: OptionButton
var create_loc_file_button: Button
var translation_table: Tree
var explanation_text: TextEdit
var file_dialog: EditorFileDialog
var save_file_dialog: EditorFileDialog
var progress_bar: ProgressBar
var status_label: Label

# Supported languages
var languages = {
	"Inglés": "en",
	"Español": "es",
	"Francés": "fr",
	"Alemán": "de",
	"Japonés": "ja",
	"Italiano": "it",
	"Portugués": "pt",
	"Ruso": "ru",
	"Chino (Simplificado)": "zh",
	"Neerlandés": "nl",
	"Polaco": "pl",
	"Sueco": "sv",
	"Coreano": "ko",
	"Turco": "tr",
	"Árabe": "ar",
	"Checo": "cs",
	"Danés": "da",
	"Finés": "fi",
	"Griego": "el",
	"Húngaro": "hu",
	"Noruego": "no",
	"Ucraniano": "uk"
}

# Data and state
var current_loc_file: String
var csv_data: Array = []
var original_es_values: Dictionary = {}
var translations: Dictionary = {}
var explanations: Dictionary = {}
var explanations_file: String = "res://addons/translai/explanations.txt"
var metrics_file: String = "res://addons/translai/translation_metrics.csv"
var translation_times: Array = []
var translated_lines: int = 0
var total_translated_cells: int = 0
var total_language_cells: int = 0
var is_project_fully_translated: bool = false
var manual_modifications_by_lang: Dictionary = {}
var total_translation_time: float = 0.0
var is_translating: bool = false

func _enter_tree():
	print("Cargando árbol, cargando interfaz de usuario...")
	dock = preload("res://addons/translai/dock.tscn").instantiate()
	
	# Initialize the main window
	window = Window.new()
	window.title = "TranslAI: Traductor de Localización con AI"
	window.size = Vector2i(600, 500)
	window.min_size = Vector2i(300, 300)
	window.add_child(dock)
	window.close_requested.connect(_on_window_close_requested)
	
	dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Add window to the scene tree
	add_child(window)
	await get_tree().process_frame
	
	# Initialize UI elements
	loc_file_input = dock.get_node("VBoxContainer/HBoxContainer/LocFileInput")
	tone_input = dock.get_node("VBoxContainer/HBoxContainer2/ToneInput")
	character_id_input = dock.get_node("VBoxContainer/HBoxContainer3/CharacterIDInput")
	language_option = dock.get_node("VBoxContainer/LanguageOption")
	source_language_option = dock.get_node("VBoxContainer/SourceLanguageOption")
	scan_button = dock.get_node("VBoxContainer/ScanButton")
	translate_button = dock.get_node("VBoxContainer/TranslateButton")
	translate_all_button = dock.get_node("VBoxContainer/TranslateAllButton")
	add_row_button = dock.get_node("VBoxContainer/AddRowButton")
	save_button = dock.get_node("VBoxContainer/SaveButton")
	add_language_button = dock.get_node("VBoxContainer/HBoxContainer4/AddLanguageButton")
	add_language_selector = dock.get_node("VBoxContainer/HBoxContainer4/AddLanguageSelector")
	create_loc_file_button = dock.get_node("VBoxContainer/CreateLocFileButton")
	translation_table = dock.get_node("VBoxContainer/TranslationTable")
	explanation_text = dock.get_node("VBoxContainer/ExplanationText")
	
	# Add ProgressBar and Label after TranslateAllButton
	var vbox = dock.get_node("VBoxContainer")
	progress_bar = ProgressBar.new()
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.visible = false
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	vbox.add_child(progress_bar)
	
	status_label = Label.new()
	status_label.text = ""
	vbox.add_child(status_label)
	
	# Move ProgressBar and StatusLabel to appropriate positions
	vbox.move_child(progress_bar, vbox.get_child_count() - 2)
	vbox.move_child(status_label, vbox.get_child_count() - 2)
	
	# Set size flags for UI elements
	for node in [loc_file_input, tone_input, character_id_input, translation_table]:
		if node and node.is_inside_tree():
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if explanation_text and explanation_text.is_inside_tree():
		explanation_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		explanation_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		explanation_text.custom_minimum_size.y = 100
	
	# Initialize file dialogs
	file_dialog = EditorFileDialog.new()
	file_dialog.add_filter("*.csv ; Archivos CSV")
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.popup_window = false
	file_dialog.transient = true
	file_dialog.exclusive = false
	add_child(file_dialog)
	
	save_file_dialog = EditorFileDialog.new()
	save_file_dialog.add_filter("*.csv ; Archivos CSV")
	save_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_file_dialog.current_path = "res://localization.csv"
	save_file_dialog.file_selected.connect(_on_save_file_selected)
	save_file_dialog.popup_window = false
	save_file_dialog.transient = true
	save_file_dialog.exclusive = false
	add_child(save_file_dialog)
	
	# Connect file picker button
	var file_picker_button = dock.get_node("VBoxContainer/HBoxContainer/FilePickerButton")
	if file_picker_button and file_picker_button.is_inside_tree():
		file_picker_button.pressed.connect(_on_file_picker_pressed)
	
	# Populate language dropdowns
	for lang in languages.keys():
		if language_option and language_option.is_inside_tree():
			language_option.add_item(lang)
		if source_language_option and source_language_option.is_inside_tree():
			source_language_option.add_item(lang)
		if add_language_selector and add_language_selector.is_inside_tree():
			add_language_selector.add_item(lang)
	if source_language_option and source_language_option.is_inside_tree():
		source_language_option.select(0)
	
	# Connect signals for buttons and table
	var signal_connections = [
		[scan_button, _on_scan_pressed],
		[translate_button, _on_translate_pressed],
		[translate_all_button, _on_translate_all_pressed],
		[add_row_button, _on_add_row_pressed],
		[save_button, _on_save_pressed],
		[add_language_button, _on_add_language_pressed],
		[create_loc_file_button, _on_create_loc_file_pressed],
		[translation_table, _on_table_item_edited]
	]
	for connection in signal_connections:
		var node = connection[0]
		var signal_func = connection[1]
		if node and node.is_inside_tree():
			if "pressed" in node:
				node.pressed.connect(signal_func)
			else:
				node.item_edited.connect(signal_func)
	
	# Initialize manual_modifications_by_lang with default languages if empty
	if manual_modifications_by_lang.is_empty():
		manual_modifications_by_lang["en"] = 0
		manual_modifications_by_lang["es"] = 0
	
	# Load existing metrics
	load_metrics()
	
	# Show the window centered
	if window and window.is_inside_tree():
		window.popup_centered()
		print("Ventana abierta en el centro, visible: ", window.visible)

func _exit_tree():
	print("Saliendo del árbol")
	if window and is_instance_valid(window):
		window.queue_free()
	if file_dialog and is_instance_valid(file_dialog):
		file_dialog.queue_free()
	if save_file_dialog and is_instance_valid(save_file_dialog):
		save_file_dialog.queue_free()
	if toolbar_button and is_instance_valid(toolbar_button):
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()

func _on_window_close_requested():
	if window and window.is_inside_tree():
		window.hide()
		print("Cierre de ventana solicitado, ocultando, visible: ", window.visible)

func _on_file_picker_pressed():
	if file_dialog and file_dialog.is_inside_tree():
		if window and window.is_inside_tree():
			window.move_to_foreground()
		file_dialog.popup_centered()
		print("Explorador de archivos abierto")
	else:
		print("Error: file_dialog no está disponible o no está en el árbol")

func _on_file_selected(path: String):
	if loc_file_input and loc_file_input.is_inside_tree():
		print("Archivo seleccionado: ", path)
		loc_file_input.text = path
		current_loc_file = path
		if window and window.is_inside_tree():
			window.show()
			window.move_to_foreground()
			print("Ventana del plugin traída al frente después de seleccionar el archivo")
	else:
		print("Error: loc_file_input no está disponible o no está en el árbol")

func _on_save_file_selected(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		var header = ["key"]
		for lang_code in languages.values():
			header.append(lang_code)
		file.store_csv_line(header)
		var sample_row = ["SAMPLE_KEY"]
		for _i in range(1, header.size()):
			sample_row.append("")
		file.store_csv_line(sample_row)
		file.close()
		print("localization.csv creado con éxito.")
		if loc_file_input and loc_file_input.is_inside_tree():
			loc_file_input.text = path
		current_loc_file = path
		if window and window.is_inside_tree():
			window.move_to_foreground()
			print("Ventana del plugin traída al frente después de guardar el archivo")
	else:
		print("Error: No se pudo crear el archivo en ", path)

func _on_scan_pressed():
	if not loc_file_input or not loc_file_input.is_inside_tree():
		print("Error: LocFileInput no disponible o no en el árbol, no se puede escanear!")
		return
	current_loc_file = loc_file_input.text.strip_edges()
	if not current_loc_file.ends_with(".csv") or not FileAccess.file_exists(current_loc_file):
		print("¡Por favor, especifica un archivo .csv válido de localización o crea uno nuevo!")
		return
	
	_do_scan()

func _do_scan():
	csv_data.clear()
	translations.clear()
	original_es_values.clear()
	translation_table.clear()
	if explanation_text and explanation_text.is_inside_tree():
		explanation_text.text = ""
	
	var file = FileAccess.open(current_loc_file, FileAccess.READ)
	if not file:
		print("¡Fallo al abrir el archivo!")
		return
	
	var header = file.get_csv_line()
	if header.size() < 1 or header[0] != "key":
		print("Error: El CSV debe tener 'key' como primera columna.")
		file.close()
		return
	
	# Load the rest of the CSV data
	var temp_data = [header]
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() >= 1 and line[0] != "":
			# Ensure the line matches the header size without adding extra commas
			while line.size() < header.size():
				line.append("")
			temp_data.append(line)
	file.close()
	
	csv_data = temp_data
	
	# Save the updated CSV
	var save_file = FileAccess.open(current_loc_file, FileAccess.WRITE)
	if save_file:
		for line in csv_data:
			save_file.store_csv_line(line)
		save_file.close()
		print("CSV cargado correctamente.")
	else:
		print("Error: No se pudo guardar el CSV.")
	
	# Set up translation table
	translation_table.set_column_titles_visible(true)
	translation_table.columns = header.size()
	for i in range(header.size()):
		translation_table.set_column_title(i, header[i])
		translation_table.set_column_expand(i, true)
	
	var source_lang = languages[languages.keys()[source_language_option.selected]]
	var source_index = header.find(source_lang)
	if source_index == -1:
		print("Idioma de origen '" + source_lang + "' no encontrado en el CSV!")
		return
	
	for line in csv_data.slice(1):
		var item = translation_table.create_item()
		for col in range(header.size()):
			var text = line[col]
			if text.begins_with("\"") and text.ends_with("\""):
				text = text.substr(1, text.length() - 2)
			item.set_text(col, text)
			item.set_editable(col, true)
	
	# Initialize translations
	for line in csv_data.slice(1):
		var key = line[0]
		var target_lang = languages[languages.keys()[language_option.selected]]
		var loc_index = header.find(target_lang)
		if loc_index != -1:
			var current_text = line[loc_index] if line.size() > loc_index else ""
			if current_text.begins_with("\"") and current_text.ends_with("\""):
				current_text = current_text.substr(1, current_text.length() - 2)
			translations[key] = current_text if current_text and current_text.strip_edges() != "" else ""
		else:
			translations[key] = ""
	
	for line in csv_data.slice(1):
		var key = line[0]
		var source_text = line[source_index] if line.size() > source_index else ""
		if source_text.begins_with("\"") and source_text.ends_with("\""):
			source_text = source_text.substr(1, source_text.length() - 2)
		var target_lang = languages[languages.keys()[language_option.selected]]
		var loc_index = header.find(target_lang)
		if loc_index != -1:
			var current_text = line[loc_index] if line.size() > loc_index else ""
			if current_text.begins_with("\"") and current_text.ends_with("\""):
				current_text = current_text.substr(1, current_text.length() - 2)
			if source_text != null and source_text.strip_edges() != "":
				translations[key] = current_text
			else:
				original_es_values[key] = current_text
				translations[key] = ""
	
	for key in translations.keys():
		var found_line = null
		for line in csv_data.slice(1):
			if line[0] == key:
				found_line = line
				break
		if found_line:
			var source_text = found_line[source_index] if found_line.size() > source_index else ""
			if source_text.begins_with("\"") and source_text.ends_with("\""):
				source_text = source_text.substr(1, source_text.length() - 2)
			var target_lang = languages[languages.keys()[language_option.selected]]
			var loc_index = header.find(target_lang)
			if loc_index != -1:
				var current_text = found_line[loc_index] if found_line.size() > loc_index else ""
				if current_text.begins_with("\"") and current_text.ends_with("\""):
					current_text = current_text.substr(1, current_text.length() - 2)
				if source_text == null or source_text.strip_edges() == "":
					translations[key] = ""
	
	compute_metrics()
	load_explanations()
	update_explanation_text()

func _on_translate_pressed():
	if translations.is_empty():
		print("¡Por favor, escanea un archivo de localización primero!")
		return
	_do_scan()
	_do_translate()

func _on_translate_all_pressed():
	if translations.is_empty():
		print("¡Por favor, escanea un archivo de localización primero!")
		return
	
	print("Iniciando Traducir Todo...")
	_do_scan()
	_do_translate_all()

func _do_translate_all():
	is_translating = true
	var start_time = Time.get_ticks_msec()
	translation_times.clear()
	translated_lines = 0
	manual_modifications_by_lang.clear()
	
	var source_lang = languages[languages.keys()[source_language_option.selected]]
	var source_index = csv_data[0].find(source_lang)
	if source_index == -1:
		print("Idioma de origen '" + source_lang + "' no encontrado en el CSV!")
		is_translating = false
		return
	
	# Collect all target languages
	var target_langs = []
	for col in csv_data[0]:
		if col != "key" and col != source_lang and col in languages.values():
			target_langs.append(col)
	
	if target_langs.is_empty():
		print("No se encontraron idiomas objetivo en el CSV!")
		is_translating = false
		return
	
	# Calculate total cells to translate
	var total_cells_to_translate = 0
	var cells_to_translate = []
	for target_lang in target_langs:
		var loc_index = csv_data[0].find(target_lang)
		if loc_index == -1:
			print("Idioma objetivo '" + target_lang + "' no encontrado en el CSV para traducción masiva!")
			continue
		for line in csv_data.slice(1):
			var key = line[0]
			var original = line[source_index] if line.size() > source_index else ""
			if not original or not original.strip_edges():
				continue
			var current_text = line[loc_index] if line.size() > loc_index else ""
			if current_text.strip_edges() == "":
				total_cells_to_translate += 1
				cells_to_translate.append([key, target_lang, loc_index])
	
	if total_cells_to_translate == 0:
		print("No hay celdas para traducir: todas las celdas ya están traducidas o no tienen texto fuente.")
		is_translating = false
		progress_bar.visible = false
		status_label.text = "No hay nada que traducir."
		return
	
	progress_bar.max_value = total_cells_to_translate
	progress_bar.value = 0
	progress_bar.visible = true
	status_label.text = "Iniciando traducción de todos los idiomas..."
	
	var current_cell_index = 0
	for cell in cells_to_translate:
		var key = cell[0]
		var target_lang = cell[1]
		var loc_index = cell[2]
		
		var original = ""
		var target_line = null
		var original_es = ""
		for line in csv_data.slice(1):
			if line[0] == key:
				original = line[source_index] if line.size() > source_index else ""
				if not original or not original.strip_edges():
					continue
				original_es = line[loc_index] if line.size() > loc_index else ""
				target_line = line
				break
		if not original or not target_line:
			continue
		
		# Check if the key is a standalone term
		var is_standalone = original.is_valid_identifier() or (original.length() <= 10 and not "[" in original and not " " in original)
		var text_to_translate = original
		
		current_cell_index += 1
		progress_bar.value = current_cell_index
		status_label.text = "Traduciendo " + str(current_cell_index) + "/" + str(total_cells_to_translate) + " celdas (idioma: " + target_lang + ")..."
		
		var context = original
		var tone = "regular"
		var translate_start = Time.get_ticks_msec()
		var deepl_result = await translate_with_deepl(text_to_translate, target_lang)
		var translate_time = (Time.get_ticks_msec() - translate_start) / 1000.0
		translation_times.append(translate_time)
		if deepl_result.begins_with("Traducción fallida"):
			translations[key] = original_es
			continue
		
		var final_result = deepl_result
		var explanation = "Traducción inicial de DeepL: " + deepl_result
		if not is_standalone:
			var ai_response = await refine_with_openai(deepl_result, target_lang, tone, text_to_translate, context)
			if ai_response is Dictionary and ai_response.has("explanation") and not ai_response["explanation"].begins_with("Refinamiento fallida"):
				final_result = ai_response["translation"].strip_edges().replace("'", "").replace("\"", "")
				explanation = ai_response["explanation"]
		else:
			# For standalone terms, preserve case and avoid over-refinement
			final_result = deepl_result
			if original == original.to_upper():
				final_result = final_result.to_upper()
			explanation = "Traducción directa de DeepL para término independiente."
		
		if final_result == key:
			continue
		
		var translated_text = final_result
		translated_text = fix_punctuation(translated_text, original, target_lang)
		translations[key] = translated_text
		var timestamp = Time.get_datetime_string_from_system()
		explanations[translated_text] = "[" + timestamp + "] " + explanation
		translated_lines += 1
		total_translated_cells += 1
		
		while target_line.size() <= loc_index:
			target_line.append("")
		target_line[loc_index] = translated_text
		
		if translation_table and translation_table.is_inside_tree():
			for item in translation_table.get_root().get_children():
				if item.get_text(0) == key:
					item.set_text(loc_index, translated_text)
					break
		
		save_to_localization_file(target_lang, false)
	
	# Restore original values
	for target_lang in target_langs:
		var loc_index = csv_data[0].find(target_lang)
		if loc_index == -1:
			continue
		for line in csv_data.slice(1):
			var key = line[0]
			var source_text = line[source_index] if line.size() > source_index else ""
			if (not source_text or not source_text.strip_edges()) and original_es_values.has(key):
				while line.size() <= loc_index:
					line.append("")
				line[loc_index] = original_es_values[key]
				if translation_table and translation_table.is_inside_tree():
					for item in translation_table.get_root().get_children():
						if item.get_text(0) == key:
							item.set_text(loc_index, original_es_values[key])
							break
	
	progress_bar.visible = false
	status_label.text = "Traducción de todos los idiomas completada."
	
	compute_metrics()
	var end_time = Time.get_ticks_msec()
	var session_time = (end_time - start_time) / 1000.0
	total_translation_time += session_time
	
	var metrics_report = (
		"Métricas de Traducción:\n" +
		"- Tiempo total de traducción: " + str(total_translation_time) + " segundos\n" +
		"- Tiempo de esta sesión: " + str(session_time) + " segundos\n" +
		"- Celdas traducidas con IA (esta sesión): " + str(translated_lines) + "\n" +
		"- Total de celdas traducidas con IA: " + str(total_translated_cells) + "\n" +
		"- Total de celdas en columnas de idioma: " + str(total_language_cells) + "\n" +
		"- Proyecto completamente traducido: " + ("Sí" if is_project_fully_translated else "No")
	)
	print(metrics_report)
	
	if explanation_text and explanation_text.is_inside_tree():
		explanation_text.text += "\n" + metrics_report
	
	var total_lines = csv_data.size() - 1
	var manual_mods = max(0, total_lines - translated_lines)
	for target_lang in target_langs:
		if manual_mods > 0:
			manual_modifications_by_lang[target_lang] = manual_mods
	
	save_explanations()
	save_metrics()
	is_translating = false
	_deferred_reimport(current_loc_file)

func _do_translate():
	is_translating = true
	var start_time = Time.get_ticks_msec()
	translation_times.clear()
	translated_lines = 0
	manual_modifications_by_lang.clear()
	
	var target_lang = languages[languages.keys()[language_option.selected]]
	var source_lang = languages[languages.keys()[source_language_option.selected]]
	var tone = tone_input.text.strip_edges()
	var character_id = character_id_input.text.strip_edges() if character_id_input else ""
	if tone == "":
		print("¡Por favor, ingresa un tono!")
		is_translating = false
		return
	var loc_index = csv_data[0].find(target_lang)
	var source_index = csv_data[0].find(source_lang)
	if loc_index == -1 or source_index == -1:
		print("Idioma objetivo o de origen no encontrado en el CSV!")
		is_translating = false
		return
	
	var total_keys_to_translate = 0
	var keys_to_translate = []
	for key in translations.keys():
		var should_translate = true
		if character_id != "" and not key.begins_with(character_id):
			should_translate = false
		var current_translation = translations.get(key, "")
		if current_translation.strip_edges() != "":
			should_translate = false
		var original = ""
		for line in csv_data.slice(1):
			if line[0] == key:
				original = line[source_index] if line.size() > source_index else ""
				break
		if not original or not original.strip_edges():
			should_translate = false
		if should_translate:
			total_keys_to_translate += 1
			keys_to_translate.append(key)
	
	if total_keys_to_translate == 0:
		print("No hay claves para traducir con los filtros actuales.")
		is_translating = false
		progress_bar.visible = false
		status_label.text = "No hay nada que traducir con los filtros actuales."
		return
	
	progress_bar.max_value = total_keys_to_translate
	progress_bar.value = 0
	progress_bar.visible = true
	status_label.text = "Iniciando traducción..."
	
	var current_key_index = 0
	print("Iniciando traducción desde: ", source_lang, " a: ", target_lang)
	
	for key in keys_to_translate:
		var current_translation = translations.get(key, "")
		if current_translation.strip_edges() != "":
			continue
		
		var original = ""
		var target_line = null
		var original_es = ""
		for line in csv_data.slice(1):
			if line[0] == key:
				original = line[source_index] if line.size() > source_index else ""
				if not original or not original.strip_edges():
					continue
				original_es = line[loc_index] if line.size() > loc_index else ""
				target_line = line
				break
		if not original or not target_line:
			continue
		
		# Check if the key is a standalone term
		var is_standalone = original.is_valid_identifier() or (original.length() <= 10 and not "[" in original and not " " in original)
		var text_to_translate = original
		
		current_key_index += 1
		progress_bar.value = current_key_index
		status_label.text = "Traduciendo " + str(current_key_index) + "/" + str(total_keys_to_translate) + " filas..."
		
		var context = original
		var translate_start = Time.get_ticks_msec()
		var deepl_result = await translate_with_deepl(text_to_translate, target_lang)
		var translate_time = (Time.get_ticks_msec() - translate_start) / 1000.0
		translation_times.append(translate_time)
		if deepl_result.begins_with("Traducción fallida"):
			translations[key] = original_es
			continue
		
		var final_result = deepl_result
		var explanation = "Traducción inicial de DeepL: " + deepl_result
		if not is_standalone:
			var ai_response = await refine_with_openai(deepl_result, target_lang, tone, text_to_translate, context)
			if ai_response is Dictionary and ai_response.has("explanation") and not ai_response["explanation"].begins_with("Refinamiento fallida"):
				final_result = ai_response["translation"].strip_edges().replace("'", "").replace("\"", "")
				explanation = ai_response["explanation"]
		else:
			# For standalone terms, preserve case and avoid over-refinement
			final_result = deepl_result
			if original == original.to_upper():
				final_result = final_result.to_upper()
			explanation = "Traducción directa de DeepL para término independiente."
		
		if final_result == key:
			continue
		
		var translated_text = final_result
		translated_text = fix_punctuation(translated_text, original, target_lang)
		translations[key] = translated_text
		var timestamp = Time.get_datetime_string_from_system()
		explanations[translated_text] = "[" + timestamp + "] " + explanation
		translated_lines += 1
		total_translated_cells += 1
		
		while target_line.size() <= loc_index:
			target_line.append("")
		target_line[loc_index] = translated_text
		
		if translation_table and translation_table.is_inside_tree():
			for item in translation_table.get_root().get_children():
				if item.get_text(0) == key:
					item.set_text(loc_index, translated_text)
					break
	
	for line in csv_data.slice(1):
		var key = line[0]
		var source_text = line[source_index] if line.size() > source_index else ""
		if (not source_text or not source_text.strip_edges()) and original_es_values.has(key):
			while line.size() <= loc_index:
				line.append("")
			line[loc_index] = original_es_values[key]
			if translation_table and translation_table.is_inside_tree():
				for item in translation_table.get_root().get_children():
					if item.get_text(0) == key:
						item.set_text(loc_index, original_es_values[key])
						break
	
	progress_bar.visible = false
	status_label.text = "Traducción completada."
	
	compute_metrics()
	var end_time = Time.get_ticks_msec()
	var session_time = (end_time - start_time) / 1000.0
	total_translation_time += session_time
	
	var metrics_report = (
		"Métricas de Traducción:\n" +
		"- Tiempo total de traducción: " + str(total_translation_time) + " segundos\n" +
		"- Tiempo de esta sesión: " + str(session_time) + " segundos\n" +
		"- Celdas traducidas con IA (esta sesión): " + str(translated_lines) + "\n" +
		"- Total de celdas traducidas con IA: " + str(total_translated_cells) + "\n" +
		"- Total de celdas en columnas de idioma: " + str(total_language_cells) + "\n" +
		"- Proyecto completamente traducido: " + ("Sí" if is_project_fully_translated else "No")
	)
	print(metrics_report)
	
	if explanation_text and explanation_text.is_inside_tree():
		explanation_text.text += "\n" + metrics_report
	
	var total_lines = csv_data.size() - 1
	var manual_mods = max(0, total_lines - translated_lines)
	if manual_mods > 0:
		manual_modifications_by_lang[target_lang] = manual_mods
	
	save_explanations()
	save_metrics()
	save_to_localization_file(target_lang, false)
	is_translating = false
	_deferred_reimport(current_loc_file)

func compute_metrics():
	var header = csv_data[0]
	var language_columns = 0
	for col in header:
		if col != "key" and col in languages.values():
			language_columns += 1
	total_language_cells = (csv_data.size() - 1) * language_columns
	print("Total celdas en columnas de idioma: ", total_language_cells)
	
	is_project_fully_translated = true
	for line in csv_data.slice(1):
		for col_idx in range(1, header.size()):
			var cell = line[col_idx] if line.size() > col_idx else ""
			if not cell or not cell.strip_edges():
				is_project_fully_translated = false
				break
		if not is_project_fully_translated:
			break
	print("Proyecto completamente traducido: ", is_project_fully_translated)

func _on_add_row_pressed():
	var dialog = AcceptDialog.new()
	add_child(dialog)
	await get_tree().process_frame
	dialog.title = "Añadir Nuevas Filas"
	dialog.size = Vector2i(400, 200)
	
	if window and window.is_inside_tree():
		window.move_to_foreground()
	dialog.popup_window = false
	dialog.transient = true
	dialog.exclusive = false
	dialog.popup_centered()
	
	var container = VBoxContainer.new()
	var id_label = Label.new()
	id_label.text = "Identificador de Personaje:"
	var id_input = LineEdit.new()
	id_input.placeholder_text = "Ej: NPC1"
	var count_label = Label.new()
	count_label.text = "Número de Filas:"
	var count_input = SpinBox.new()
	count_input.min_value = 1
	count_input.max_value = 100
	count_input.value = 1
	
	container.add_child(id_label)
	container.add_child(id_input)
	container.add_child(count_label)
	container.add_child(count_input)
	dialog.add_child(container)
	
	dialog.confirmed.connect(func():
		var character_id = id_input.text.strip_edges()
		var row_count = int(count_input.value)
		if character_id == "":
			print("Error: Debe especificar un identificador de personaje.")
			return
		
		_do_add_rows(character_id, row_count)
		dialog.queue_free()
	)
	
	await get_tree().process_frame
	if dialog.is_inside_tree():
		dialog.popup_centered()
	else:
		print("Error: No se pudo abrir el diálogo para añadir filas")

func _do_add_rows(character_id: String, row_count: int):
	var last_index = -1
	for line in csv_data.slice(1):
		if line[0].begins_with(character_id + "_"):
			var suffix = line[0].replace(character_id + "_", "")
			if suffix.is_valid_int():
				last_index = max(last_index, suffix.to_int())
	
	var new_keys = []
	for i in range(row_count):
		var suffix = str(last_index + i + 1).pad_zeros(2)
		var new_key = character_id + "_" + suffix
		new_keys.append(new_key)
		var new_row = [new_key]
		for j in range(1, csv_data[0].size()):
			new_row.append("")
		
		csv_data.append(new_row)
		translations[new_key] = ""
		
		var item = translation_table.create_item()
		for col in range(new_row.size()):
			item.set_text(col, new_row[col])
			item.set_editable(col, true)
	
	compute_metrics()
	save_to_localization_file(languages[languages.keys()[language_option.selected]])

func _on_save_pressed():
	if not current_loc_file:
		print("¡Por favor, selecciona un archivo de localización primero o crea uno nuevo!")
		return
	save_to_localization_file(languages[languages.keys()[language_option.selected]])
	compute_metrics()

func _on_add_language_pressed():
	var new_lang = languages[languages.keys()[add_language_selector.selected]]
	if new_lang in csv_data[0]:
		print("El idioma '" + new_lang + "' ya existe en el CSV!")
		return
	
	_do_add_language(new_lang)

func _do_add_language(new_lang: String):
	csv_data[0].append(new_lang)
	for line in csv_data.slice(1):
		line.append("")
	
	translation_table.columns = csv_data[0].size()
	translation_table.clear()
	translation_table.set_column_titles_visible(true)
	for i in range(csv_data[0].size()):
		translation_table.set_column_title(i, csv_data[0][i])
		translation_table.set_column_expand(i, true)
	for line in csv_data.slice(1):
		var item = translation_table.create_item()
		for col in range(line.size()):
			item.set_text(col, line[col])
			item.set_editable(col, true)
	
	compute_metrics()
	save_to_localization_file(new_lang)

func _on_table_item_edited():
	var selected_item = translation_table.get_selected()
	if not selected_item:
		return
	var col = translation_table.get_selected_column()
	var new_text = selected_item.get_text(col)
	var old_key = selected_item.get_text(0)
	var header = csv_data[0]
	
	var target_lang = languages[languages.keys()[language_option.selected]]
	var loc_index = header.find(target_lang)
	
	_do_edit_cell(old_key, col, new_text)

func _do_edit_cell(old_key: String, col: int, new_text: String):
	var header = csv_data[0]
	var target_lang = languages[languages.keys()[language_option.selected]]
	var loc_index = header.find(target_lang)
	
	for line in csv_data.slice(1):
		if line[0] == old_key:
			while line.size() <= col:
				line.append("")
			line[col] = new_text
			if col == 0:
				var new_key = new_text
				translations.erase(old_key)
				translations[new_key] = line[loc_index] if line.size() > loc_index else ""
				if original_es_values.has(old_key):
					var es_value = original_es_values[old_key]
					original_es_values.erase(old_key)
					original_es_values[new_key] = es_value
				for item in translation_table.get_root().get_children():
					if item.get_text(0) == old_key:
						item.set_text(0, new_key)
			elif col == loc_index:
				translations[old_key] = new_text
				if original_es_values.has(old_key):
					original_es_values[old_key] = new_text
	
	if col >= 1:
		var lang_code = header[col]
		if not manual_modifications_by_lang.has(lang_code):
			manual_modifications_by_lang[lang_code] = 0
		manual_modifications_by_lang[lang_code] += 1
	
	compute_metrics()
	save_to_localization_file(target_lang)

func _on_create_loc_file_pressed():
	if save_file_dialog and save_file_dialog.is_inside_tree():
		if window and window.is_inside_tree():
			window.move_to_foreground()
		save_file_dialog.popup_centered()
		print("Diálogo de guardado abierto")
	else:
		print("Error: save_file_dialog no está disponible o no está en el árbol")

func translate_with_deepl(text: String, target_lang: String) -> String:
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = "https://api-free.deepl.com/v2/translate"
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	var source_lang = languages[languages.keys()[source_language_option.selected]].to_upper()
	var body = "auth_key=c259c901-3d49-408f-ad63-38606137b095:fx&text=" + text.uri_encode() + "&target_lang=" + target_lang.to_upper() + "&source_lang=" + source_lang
	
	var error = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return "Traducción fallida: Error de solicitud " + str(error)
	
	var result = await http.request_completed
	http.queue_free()
	
	var response_code = result[1]
	var response_body = result[3].get_string_from_utf8()
	
	if response_code != 200:
		return "Traducción fallida: Error " + str(response_code)
	
	var json = JSON.new()
	var parse_result = json.parse(response_body)
	if parse_result != OK or not json.data.has("translations") or json.data["translations"].size() == 0:
		return "Traducción fallida: Respuesta inválida"
	
	var translated_text = json.data["translations"][0]["text"]
	return translated_text

func refine_with_openai(deepl_result: String, target_lang: String, tone: String, original_text: String, context: String) -> Dictionary:
	var translation_failed = deepl_result.strip_edges().to_lower() == original_text.to_lower() or deepl_result.strip_edges() == ""
	var prompt = (
		"Refina la siguiente traducción al idioma '" + target_lang + "' para que sea natural, precisa y conversacional, siguiendo el tono '" + tone + "'. " +
		"The original text contains special tags (e.g., [wave amplitude=10], [rainbow], [shake rate=20 level=10]) that must be preserved exactly as they appear, including their attributes and content. " +
		"Translate only the text outside and inside these tags, and adjust the tag positions to surround the equivalent words or phrases in the target language. " +
		"Do not duplicate or translate the tag names or attributes themselves (e.g., [rainbow] should stay [rainbow], not become [arcoiris]). " +
		"If the initial translation is identical to the original text or empty, it means the translation failed; in this case, provide a correct translation for the original text in the target language. " +
		"If the initial translation is still in the source language ('" + original_text + "'), translate it properly into the target language. " +
		"Ensure the full sentence is translated without cut-offs, maintaining proper spacing, punctuation, and grammar. " +
		"Original text: '" + original_text + "'\n" +
		"Initial translation: '" + deepl_result + "'\n" +
		"Context: '" + context + "'\n" +
		"Provide the refined translation and a brief explanation of your changes, ensuring tags are correctly placed around the translated equivalents."
	)

	
	var data = {
		"model": "gpt-4",
		"messages": [
			{"role": "system", "content": "You are an expert translator who refines translations, preserving special tags and adjusting their positions to match translated equivalents. If the initial translation matches the original text or is empty, provide a correct translation."},
			{"role": "user", "content": prompt}
		],
		"max_tokens": 500,
		"temperature": 0.7
	}
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer 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"
	]
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	var error = http_request.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(data))
	if error != OK:
		http_request.queue_free()
		return {"translation": deepl_result, "explanation": "Refinamiento fallida: Error en la solicitud HTTP"}
	
	var response = await http_request.request_completed
	http_request.queue_free()
	
	var response_code = response[1]
	var body = response[3].get_string_from_utf8()
	
	if response_code != 200:
		return {"translation": deepl_result, "explanation": "Refinamiento fallida: Código de respuesta " + str(response_code)}
	
	var json = JSON.new()
	var parse_result = json.parse(body)
	if parse_result != OK:
		return {"translation": deepl_result, "explanation": "Refinamiento fallida: Error al parsear JSON"}
	
	var response_data = json.data
	if not response_data.has("choices") or response_data["choices"].size() == 0:
		return {"translation": deepl_result, "explanation": "Refinamiento fallida: No se encontraron opciones en la respuesta"}
	
	var ai_response = response_data["choices"][0]["message"]["content"]
	var translation = ai_response.split("Traducción refinada: ")[1].split("\n")[0].strip_edges() if "Traducción refinada: " in ai_response else deepl_result
	var explanation = ai_response.split("Explicación: ")[1].strip_edges() if "Explicación: " in ai_response else "Sin explicación proporcionada"
	
	return {"translation": translation, "explanation": explanation}

func fix_punctuation(text: String, original: String, target_lang: String) -> String:
	var result = text
	# Remove extra spaces before ellipses
	result = result.replace(" ...", "...")
	# Ensure question and exclamation marks match the original
	if original.ends_with("?") and not result.ends_with("?"):
		result = result.trim_suffix("...").trim_suffix(".") + "?"
	elif original.ends_with("!") and not result.ends_with("!"):
		result = result.trim_suffix("...").trim_suffix(".") + "!"
	# Remove unnecessary exclamation marks if original doesn't have them
	if not original.contains("!") and result.contains("¡"):
		result = result.replace("¡", "")
	# Fix comma placement and remove incorrect commas
	if result.contains(", " + target_lang.split("_")[0].to_lower() + ","):
		result = result.replace(", " + target_lang.split("_")[0].to_lower() + ",", " " + target_lang.split("_")[0].to_lower())
	return result

func save_to_localization_file(target_lang: String, reimport: bool = true):
	var loc_index = csv_data[0].find(target_lang)
	var source_index = csv_data[0].find(languages[languages.keys()[source_language_option.selected]])
	for line in csv_data.slice(1):
		var key = line[0]
		var source_text = line[source_index] if line.size() > source_index else ""
		if (not source_text or not source_text.strip_edges()) and original_es_values.has(key):
			while line.size() <= loc_index:
				line.append("")
			line[loc_index] = original_es_values[key]
	
	var file = FileAccess.open(current_loc_file, FileAccess.WRITE)
	if file:
		for line in csv_data:
			file.store_csv_line(line)
		file.close()
		if reimport and not is_translating:
			var timer = Timer.new()
			timer.wait_time = 0.1
			timer.one_shot = true
			timer.timeout.connect(func():
				_deferred_reimport(current_loc_file)
				timer.queue_free()
			)
			add_child(timer)
			timer.start()

func _deferred_reimport(file_path: String):
	var importer = get_editor_interface().get_resource_filesystem()
	if importer and file_path:
		importer.reimport_files([file_path])
		print("Archivo reimportado: ", file_path)

func save_explanations():
	var file = FileAccess.open(explanations_file, FileAccess.WRITE)
	if file:
		for trans in explanations.keys():
			file.store_line("Traducción: " + trans)
			file.store_line("Explicación: " + explanations[trans])
			file.store_line("")
		for lang in manual_modifications_by_lang.keys():
			file.store_line("Modificaciones Manuales (" + lang + "): " + str(manual_modifications_by_lang[lang]) + " líneas")
		var total_manual_mods = manual_modifications_by_lang.values().reduce(func(acc, val): return acc + val, 0)
		file.store_line("Modificaciones Manuales Totales: " + str(total_manual_mods) + " líneas")
		file.store_line("Tiempo Total de Traducción: " + str(total_translation_time) + " segundos")
		file.store_line("Total Celdas Traducidas con IA: " + str(total_translated_cells))
		file.store_line("Total Celdas en Columnas de Idioma: " + str(total_language_cells))
		file.store_line("Proyecto Completamente Traducido: " + ("Sí" if is_project_fully_translated else "No"))
		file.close()
		print("Explicaciones guardadas en: " + explanations_file)

func load_explanations():
	explanations.clear()
	manual_modifications_by_lang.clear()
	if FileAccess.file_exists(explanations_file):
		var file = FileAccess.open(explanations_file, FileAccess.READ)
		var current_trans = ""
		var current_explanation = ""
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.begins_with("Traducción: "):
				if current_trans != "" and current_explanation != "":
					explanations[current_trans] = current_explanation
				current_trans = line.replace("Traducción: ", "")
				current_explanation = ""
			elif line.begins_with("Explicación: "):
				current_explanation = line.replace("Explicación: ", "")
			elif line != "" and current_explanation != "":
				current_explanation += "\n" + line
			elif line.begins_with("Modificaciones Manuales ("):
				var lang_end = line.find("):")
				if lang_end != -1:
					var lang = line.substr(20, lang_end - 20)
					var count = int(line.replace("Modificaciones Manuales (" + lang + "): ", "").replace(" líneas", ""))
					manual_modifications_by_lang[lang] = count
			elif line.begins_with("Tiempo Total de Traducción:"):
				total_translation_time = float(line.replace("Tiempo Total de Traducción: ", "").replace(" segundos", ""))
			elif line.begins_with("Total Celdas Traducidas con IA:"):
				total_translated_cells = int(line.replace("Total Celdas Traducidas con IA: ", ""))
			elif line.begins_with("Total Celdas en Columnas de Idioma:"):
				total_language_cells = int(line.replace("Total Celdas en Columnas de Idioma: ", ""))
			elif line.begins_with("Proyecto Completamente Traducido:"):
				is_project_fully_translated = line.replace("Proyecto Completamente Traducido: ", "") == "Sí"
		if current_trans != "" and current_explanation != "":
			explanations[current_trans] = current_explanation
		file.close()

func load_metrics():
	if FileAccess.file_exists(metrics_file):
		var file = FileAccess.open(metrics_file, FileAccess.READ)
		if file:
			var header = file.get_csv_line()
			if header and header[0] == "metric" and header[1] == "value":
				while not file.eof_reached():
					var line = file.get_csv_line()
					if line.size() >= 2:
						if line[0].begins_with("manual_modifications_"):
							var lang = line[0].replace("manual_modifications_", "")
							manual_modifications_by_lang[lang] = int(line[1]) if line[1].is_valid_int() else 0
						elif line[0] == "total_translation_time":
							total_translation_time = float(line[1]) if line[1].is_valid_float() else 0.0
						elif line[0] == "total_translated_cells":
							total_translated_cells = int(line[1]) if line[1].is_valid_int() else 0
						elif line[0] == "total_language_cells":
							total_language_cells = int(line[1]) if line[1].is_valid_int() else 0
						elif line[0] == "is_project_fully_translated":
							is_project_fully_translated = line[1] == "true"
			file.close()
	else:
		var file = FileAccess.open(metrics_file, FileAccess.WRITE)
		if file:
			file.store_csv_line(["metric", "value"])
			for lang in manual_modifications_by_lang.keys():
				file.store_csv_line(["manual_modifications_" + lang, str(manual_modifications_by_lang[lang])])
			file.store_csv_line(["total_translation_time", "0.0"])
			file.store_csv_line(["total_translated_cells", "0"])
			file.store_csv_line(["total_language_cells", "0"])
			file.store_csv_line(["is_project_fully_translated", "false"])
			file.close()
			print("Archivo translation_metrics.csv creado con métricas iniciales completas.")

func save_metrics():
	var file = FileAccess.open(metrics_file, FileAccess.WRITE)
	if file:
		file.store_csv_line(["metric", "value"])
		for lang in manual_modifications_by_lang.keys():
			file.store_csv_line(["manual_modifications_" + lang, str(manual_modifications_by_lang[lang])])
		file.store_csv_line(["total_translation_time", str(total_translation_time)])
		file.store_csv_line(["total_translated_cells", str(total_translated_cells)])
		file.store_csv_line(["total_language_cells", str(total_language_cells)])
		file.store_csv_line(["is_project_fully_translated", str(is_project_fully_translated).to_lower()])
		file.close()
		print("Métricas guardadas en: " + metrics_file)

func update_explanation_text():
	if explanation_text and explanation_text.is_inside_tree():
		explanation_text.text = ""
		if explanations.is_empty():
			explanation_text.text = "No se han generado explicaciones aún."
		else:
			for trans in explanations.keys():
				explanation_text.text += "Traducción: " + trans + "\n"
				explanation_text.text += "Explicación: " + explanations[trans] + "\n\n"

func get_plugin_name():
	return "TranslAI: Traductor de Localización con Explicaciones de IA"
