local click_timer = nil
local click_count = 0

local function handle_click()
    click_count = click_count + 1
    if click_count == 1 then
        click_timer = mp.add_timeout(0.25, function()
            click_count = 0
            -- Toggle ModernZ OSC controls (fades out after hidetimeout=3000ms or hides immediately if clicked when visible)
            mp.commandv('script-message', 'osc-toggle')
        end)
    elseif click_count == 2 then
        if click_timer then
            click_timer:kill()
            click_timer = nil
        end
        click_count = 0
        mp.command('cycle fullscreen')
    end
end

-- Bind left click to our smart handler.
-- ModernZ OSC overrides left click when hovering over its buttons or seekbar,
-- so this handler is only executed when clicking on the video background.
mp.add_key_binding('MBTN_LEFT', 'click_handler', handle_click)

mp.add_key_binding(nil, 'prev', function()
    mp.commandv('script-message', 'macast-prev')
end)

mp.add_key_binding(nil, 'next', function()
    mp.commandv('script-message', 'macast-next')
end)
