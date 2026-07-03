-- title.lua -- タイトル画面。SPACE/ENTER で Stage1 へ。
local done = false

function OnStart(self)
  done = false
end

function OnUpdate(self, dt)
  ui:text(260, 180, "TIME ARROW", 56, 1.0, 0.85, 0.3, 1)
  ui:text(230, 250, "-- 時を先送りさせる矢 --", 24, 0.9, 0.9, 1.0, 1)
  ui:text(280, 320, "Press SPACE / ENTER to Start", 26, 1, 1, 1, 1)
  ui:text(300, 360, "A/D move  SPACE jump  E fire arrow", 20, 0.8, 0.8, 0.85, 1)

  if (keyPressed("SPACE") or keyPressed("ENTER")) and not done then
    done = true
    goToScene("scenes/stage1.json", 0.6)
  end
end
