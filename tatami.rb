#!/usr/bin/env ruby
# frozen_string_literal: true
require 'gtk3'

# ResizeGrid
class ResizeGrid < Gtk::DrawingArea
  LEFT_MOUSE_BUTTON = 1
  RGBA_SELECTED = Gdk::RGBA.new(0.6, 0.6, 0.6, 0.8)
  RGBA_UNSELECTED = Gdk::RGBA.new(0.9, 0.9, 0.9, 0.8)
  TARGET_EVENTS = Gdk::EventMask::BUTTON_PRESS_MASK |
                  Gdk::EventMask::BUTTON_RELEASE_MASK |
                  Gdk::EventMask::POINTER_MOTION_MASK |
                  Gdk::EventMask::POINTER_MOTION_HINT_MASK

  def initialize(&resize_callback)
    super()

    add_events(TARGET_EVENTS)
    @cairo_context = nil
    @drag_begin = nil
    @current_xy = nil

    signal_connect('motion_notify_event') do |_, event_motion|
      next unless @drag_begin

      @current_xy = [event_motion.x, event_motion.y]
      draw_cells
      queue_draw
    end

    signal_connect('button_press_event') do |_, event_button|
      next unless @cairo_context
      next unless event_button.button == LEFT_MOUSE_BUTTON

      @drag_begin = event_button
      draw_cells
      queue_draw
    end

    signal_connect('button_release_event') do |_, event_button|
      next unless drag_end?(event_button)

      resized_rectangle = calc_resized_rectangle
      @drag_begin = nil
      @current_xy = nil
      draw_cells
      queue_draw
      resize_callback.call(resized_rectangle)
    end

    signal_connect('draw') do
      @cairo_context = window.create_cairo_context
      draw_background
      draw_cells
      queue_draw
    end
  end

  private

  def calc_resized_rectangle
    cells = to_enum(:each_cells)
    left_top_cell = cells.detect { |row_index, column_index|
      cell_selected?(row_index, column_index)
    }
    right_bottom_cell = cells.reverse_each.detect { |row_index, column_index|
      cell_selected?(row_index, column_index)
    }
    cell_height = screen.height / rows
    cell_width = screen.width / columns
    left = left_top_cell[1] * cell_width
    top = left_top_cell[0] * cell_height
    right = right_bottom_cell[1] * cell_width + cell_width
    bottom = right_bottom_cell[0] * cell_height + cell_height
    [
      left,
      top,
      right - left,
      bottom - top
    ]
  end

  def cell_height
    (window.height - (rows + 1) * cell_margin) / rows
  end

  def cell_width
    (window.width - (columns + 1) * cell_margin) / columns
  end

  def cell_margin
    4
  end

  def cell_selected?(row_index, column_index)
    return false unless @drag_begin
    return false unless @current_xy

    if @current_xy[1] > @drag_begin.y
      top = @drag_begin.y
      bottom = @current_xy[1]
    else
      top = @current_xy[1]
      bottom = @drag_begin.y
    end

    if @current_xy[0] > @drag_begin.x
      left = @drag_begin.x
      right = @current_xy[0]
    else
      left = @current_xy[0]
      right = @drag_begin.x
    end

    left < cell_x(column_index) + cell_width &&
      right > cell_x(column_index) &&
      top < cell_y(row_index) + cell_height &&
      bottom > cell_y(row_index)
  end

  def cell_gdk_rgba(row_index, column_index)
    if cell_selected?(row_index, column_index)
      RGBA_SELECTED
    else
      RGBA_UNSELECTED
    end
  end

  def cell_x(column_index)
    cell_margin + (cell_width + cell_margin) * column_index
  end

  def cell_y(row_index)
    cell_margin + (cell_height + cell_margin) * row_index
  end

  def columns
    8
  end

  def draw_background
    @cairo_context.set_source_rgba(0, 0, 0, 0.5)
    @cairo_context.rectangle(0, 0, window.width, window.height)
    @cairo_context.fill
  end

  def draw_cell_rectangle(row_index, column_index)
    @cairo_context.set_source_gdk_rgba(cell_gdk_rgba(row_index, column_index))
    @cairo_context.rectangle(
      cell_x(column_index),
      cell_y(row_index),
      cell_width,
      cell_height
    )
    @cairo_context.fill
  end

  def draw_cells
    each_cells do |row_index, column_index|
      draw_cell_rectangle(row_index, column_index)
    end
  end

  def each_cells
    rows.times do |row_index|
      columns.times do |column_index|
        yield row_index, column_index
      end
    end
  end

  def rows
    8
  end

  def drag_end?(event_button)
    @drag_begin &&
      @drag_begin.button == event_button.button &&
      @drag_begin.device == event_button.device
  end
end

# ResizeWindow
class ResizeWindow < Gtk::Window
  def initialize(&resize_callback)
    super()

    set_default_size(window_width, window_height)
    move(window_left, window_top)
    set_title('Resize')
    set_decorated(false)
    set_transparent
    signal_connect('destroy') { Gtk.main_quit }
    signal_connect('focus_out_event') { Gtk.main_quit }
    # Gdk::EventMask::KEY_PRESS_MASK
    signal_connect('key_release_event') do |_, event_key|
      next Gdk::EventKey::PROPAGATE if event_key.modifier?
      case event_key.keyval
      when Gdk::Keyval::KEY_Escape
        Gtk.main_quit
      when Gdk::Keyval::KEY_f
        resize_callback.call(0, 0, screen.width, screen.height)
      when Gdk::Keyval::KEY_h
        resize_callback.call(0, 0, screen.width / 2, screen.height)
      when Gdk::Keyval::KEY_l
        resize_callback.call(screen.width / 2, 0, screen.width / 2, screen.height)
      else
        p event_key.keyval
      end
      Gdk::EventKey::PROPAGATE
    end
    add(ResizeGrid.new(&resize_callback))
    show_all
    set_keep_above(true)
    present
  end

  def when_grid_selected(&block)
    @resize_callback = block
  end

  private

  def window_height
    screen.height / 4
  end

  def window_left
    (screen.width - window_width) / 2
  end

  def window_top
    (screen.height - window_height) / 2
  end

  def window_width
    screen.width / 4
  end

  def set_transparent
    set_visual(screen.rgba_visual)
    css_provider = Gtk::CssProvider.new
    screen.add_style_provider(css_provider)
    css_provider.load_from_data(<<~CSS)
      window {
        background-color: transparent;
      }
    CSS
  end
end

active_window = Gdk::Screen.default.active_window
window = ResizeWindow.new do |x, y, width, height|
  active_window.unmaximize
  active_window.resize(width, height)
  active_window.move(x, y)
  Gtk.main_quit
end
Gtk.main
