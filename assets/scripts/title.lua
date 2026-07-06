-- title.lua -- タイトル画面。「動画」のコンセプトをシークバーのモチーフで見せる。SPACE/ENTERでStage1へ。
local done = false

function OnStart(self)
  done = false
  self.demoT = 0
end

function OnUpdate(self, dt)
  self.demoT = self.demoT + dt
  local W, H = SCREEN_W or 1280, SCREEN_H or 720
  local cx = W * 0.5

  ui:text(cx - 210, 150, "TIME ARROW", 56, 1.0, 0.85, 0.3, 1)
  ui:text(cx - 170, 218, "-- 時を先送りさせる矢 --", 24, 0.9, 0.9, 1.0, 1)

  -- デモ用シークバー(タイトル画面の演出。実プレイのHUDはGameManager.luaが描く)
  local barW, barH = 520, 18
  local barX, barY = cx - barW * 0.5, 280
  local demoFrac = (math.sin(self.demoT * 0.6) * 0.5 + 0.5)
  ui:rect(barX - 4, barY - 4, barW + 8, barH + 8, 0.05, 0.06, 0.09, 0.7, 8)
  ui:rect(barX, barY, barW, barH, 0.16, 0.18, 0.24, 0.9, 4)
  ui:rect(barX, barY, barW * demoFrac, barH, 0.3, 0.75, 0.95, 0.95, 4)
  ui:rect(barX + barW * demoFrac - 2, barY - 6, 4, barH + 12, 1, 0.85, 0.3, 1, 0)

  ui:text(cx - 260, 340, "刺さったオブジェクトの時間を先送りする矢を1本だけ持って、", 20, 0.85, 0.9, 1.0, 1)
  ui:text(cx - 260, 366, "動画が終わる前にゴールへ。", 20, 0.85, 0.9, 1.0, 1)

  ui:text(cx - 250, 420, "Press SPACE / ENTER / A(pad) to Start", 26, 1, 1, 1, 1)
  ui:text(cx - 260, 460, "A/D move  SPACE jump  W/S climb", 20, 0.8, 0.8, 0.85, 1)
  ui:text(cx - 260, 484, "E(hold) draw bow, aim 8-way with WASD/arrows, release to fire", 20, 0.8, 0.8, 0.85, 1)
  ui:text(cx - 260, 508, "R retry stage    Gamepad: Stick move  A jump  X(hold) draw+aim", 20, 0.8, 0.8, 0.85, 1)

  if (keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") or padPressed("START")) and not done then
    done = true
    goToScene("scenes/stage1.json", 0.6)
  end
end
