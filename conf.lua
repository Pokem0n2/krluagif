-- conf.lua for run.lua
function love.conf(t)
    t.window.title = "Vesper Hero Animation"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = false
    t.window.fullscreen = false
    t.modules.physics = false
    t.console = true
    t.identity = "vesper_test"
end
