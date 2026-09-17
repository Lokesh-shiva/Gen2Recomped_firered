-- Regression: developer-console characters must follow LOVE's text-input
-- events, which preserves Caps Lock, keyboard layouts and pasted text.
return function(game)
  local U = require("tests.drivers.util")
  U.freshSave(game)
  U.teleport(game, "MAP_G03_N00", 10, 10, "down")
  game:keypressed("`")
  local console = game.stack:top()
  assert(console and console.onTextInput, "developer console did not open")
  assert(game.textinput, "Game does not forward text input to overlays")
  game:textinput("READY_SET")
  assert(console.buffer == "READY_SET",
    "developer console lost capital letters or underscore text")
  U.log("PASS console accepts native text input")
  love.event.quit(0)
end
