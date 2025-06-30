**MarkupUI — Godot Editor Add‑on**

A Godot EditorPlugin that enables UI scene creation via a lightweight XML‑based markup language. Write your UI structure, resource references, and data bindings in a single `.godarkup` file; then generate a `.tscn` scene or preview it instantly from the Godot Editor.

---

## Features

- **XML‑based UI definition**: Define nodes, properties, and child hierarchies in a human‑readable markup format.
- **Resource embedding**: Collect textures, themes, fonts, and other assets with a dedicated `<Resources>` block.
- **Property & signal bindings**: Bind UI properties to game objects’ properties or signals using `{}` syntax:
  - `{node_id.property}` — one‑time initialization
  - `{node_id.property:signal_name}` — automatic updates on signal
- **Preview panel**: Live preview your markup directly within the Editor’s bottom dock.
- **Scene generation**: Generate `.tscn` files with ownership and packing handled for you.

## Installation

1. Copy the `addons/godarkup/` folder into your project’s `res://addons/` directory.
2. In Godot’s **Project Settings ▶️ Plugins**, enable **GodArkup**.
3. Ensure `.godarkup` files are visible in the FileSystem dock (added automatically).

## Syntax Overview

### Root Structure

```xml
<Resources> … </Resources>
<RootNode …> … </RootNode>
```

- ``: Declare asset `id` and `path` pairs.
- **UI Elements**: Any Godot `Node` type as XML tags. Attributes map to properties or signal‐handlers.

### Resource Block

```xml
<Resources>
  <ImageTexture id="icon" path="res://assets/icon.svg" />
  <Theme id="app_theme"   path="res://assets/theme.tres" />
  <Font id="custom_font"  path="res://assets/font.tres" />
</Resources>
```

### Property & Signal Binding

- **One‑time property initialize**: `value="{player1.max_health}"`
- **Dynamic binding**: `value="{player1.health:health_changed}"`

Example:

```xml
<ProgressBar
    min="0"
    max_value="{player1.max_health}"
    value="{player1.health:health_changed}"
    theme="app_theme"
    custom_minimum_size="60;0"
    size_flags_vertical="3" />
```

### Event Handling

Use `on_<signal>="method_name"` to wire UI events to script callbacks:

```xml
<Button text="Click Me" on_pressed="_on_button_pressed" />
```

## 📂 Example Markup

```xml
<Resources>
  <Theme id="main_theme" path="res://assets/theme.tres"/>
</Resources>
<VBoxContainer>
  <ProgressBar name="HealthBar"
               min="0"
               max_value="{player1.max_health}"
               value="{player1.health:health_changed}"
               theme="main_theme"
               custom_minimum_size="60;0"
               size_flags_vertical="3"/>

  <Label text="{player1.ammo:ammo_updated}" theme="main_theme"/>
</VBoxContainer>
```

## Usage

1. **Edit** your `.godarkup` file in the FileSystem dock.
2. **Select** the file and click **Tools ▶️ Generate UI Scene**.
3. A new `.tscn` will be created alongside the `.godarkup` file.
4. **Preview** live: open the **UI Markup Preview** panel at the bottom.


## License

MIT License. See [LICENSE](LICENSE) for details.

