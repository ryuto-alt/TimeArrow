-- Tutorial.lua -- stage0 チュートリアルの進行役。空エンティティ(TutorialDirector)に付ける。
-- 設計原則(2026-07 リサーチ反映): ①1ステップ=1操作、実際にできるまで次へ進まない
-- ②文言は1行の短文のみ(カルーセル/知識ダンプ廃止) ③教えるのは「必要になる直前」
-- ④達成は単調(先にやってしまっても取りこぼさない) ⑤開幕バナーが消えてからパネル登場。
-- 8ステップ: 移動→ジャンプ→見わたす→かまえ→ねらい→先送り矢→まき戻し矢→ゴール。
-- 入力デバイスを毎フレーム検出し、キーボード⇔ゲームパッドで説明とキー表示を自動で切り替える。
-- HUD側は stage0 専用エンティティ群(元は gen_stages.py 生成、現在はシーンJSONが正):
--   TutPanel(下部パネル) > TutStepTitle(未使用) / TutStepText(1行指示) / TutStepSub(未使用) /
--   TutKeyCap1,2 (+子ラベル) / TutKeyWide(+子ラベル) / TutIconFF / TutIconRW / TutCheck / TutDots
--   TutBurst(画面中央のポップ文字、HudCanvas直下)
-- ⚠ このエンジンの tweenUi の dx/dy は「相対移動」(実レイアウトを動かす)。絶対座標指定ではないので
--   出し入れは +140 → -140 のように往復で書く。
properties = {
  { name = "walkGoal", type = "float", default = 2.5,  label = "STEP1: 必要な歩行距離" },
  { name = "jumpX",    type = "float", default = 12.8, label = "STEP2: 段差を越えたと見なすX" },
}

local COL = {
  gold   = { 1.0, 0.85, 0.30 },
  cyan   = { 0.33, 0.88, 1.0 },
  purple = { 0.80, 0.60, 1.0 },
  green  = { 0.49, 1.0, 0.62 },
  red    = { 1.0, 0.45, 0.4 },
}

-- kind: 完了条件の種類 / icon: パネル左の時計アイコン
-- kb / pad: 入力デバイス別の表示(text=指示1行, keys=四角キーキャップ(最大2),
--            wide=横長キャップ, wideLabel=その文字)
local STEPS = {
  { kind = "walk", tcol = COL.gold,
    kb  = { text = "[c=55E0FF]A[/c] / [c=55E0FF]D[/c] で あるこう",
            keys = { "A", "D" } },
    pad = { text = "[c=55E0FF]Lスティック[/c] で あるこう",
            keys = {}, wide = true, wideLabel = "Lスティック" } },
  { kind = "jump", tcol = COL.gold,
    kb  = { text = "[c=FFD866]SPACE[/c] で ジャンプ！",
            keys = {}, wide = true, wideLabel = "SPACE" },
    pad = { text = "[c=FFD866]A ボタン[/c] で ジャンプ！",
            keys = { "A" } } },
  { kind = "look", tcol = COL.gold,
    kb  = { text = "[c=55E0FF]TAB[/c] ながおしで 見わたそう",
            keys = { "TAB" } },
    pad = { text = "[c=55E0FF]X[/c] ながおしで 見わたそう",
            keys = { "X" } } },
  { kind = "draw", tcol = COL.cyan, icon = "ff",
    kb  = { text = "[c=55E0FF]E[/c] を おしつづけて かまえよう",
            keys = { "E" } },
    pad = { text = "[c=55E0FF]RB[/c] を おしつづけて かまえよう",
            keys = { "RB" } } },
  { kind = "aim", tcol = COL.cyan, icon = "ff",
    kb  = { text = "かまえたまま [c=FFD866]W[/c] / [c=FFD866]S[/c] で ねらおう",
            keys = { "W", "S" } },
    pad = { text = "かまえたまま [c=FFD866]Lスティック[/c] で ねらおう",
            keys = {}, wide = true, wideLabel = "Lスティック" } },
  { kind = "shoot", tcol = COL.cyan, icon = "ff",
    kb  = { text = "はなして [c=55E0FF]とびら[/c] に あてよう！",
            keys = { "E" } },
    pad = { text = "はなして [c=55E0FF]とびら[/c] に あてよう！",
            keys = { "RB" } } },
  { kind = "rw", tcol = COL.purple, icon = "rw",
    kb  = { text = "[c=CC99FF]Q[/c] ながおしで 針山に あてよう",
            keys = { "Q" } },
    pad = { text = "[c=CC99FF]LB[/c] ながおしで 針山に あてよう",
            keys = { "LB" } } },
  { kind = "goal", tcol = COL.green,
    kb  = { text = "[c=FF6655]バー[/c]が 端に つくまえに [c=7CFF9E]ゴール[/c]へ！",
            keys = {} },
    pad = { text = "[c=FF6655]バー[/c]が 端に つくまえに [c=7CFF9E]ゴール[/c]へ！",
            keys = {} } },
}

-- 開幕バナー(GameManagerが2.4秒表示)が消えてからパネルを出す
local INTRO_PANEL_AT = 2.6
local INTRO_STEP1_AT = 3.3
local CELEB_DUR      = 1.6    -- STEP CLEAR演出→次ステップまでの間(ゆっくりめ)

local function ent(name)
  local e = scene:findEntity(name)
  if e and e:isValid() then return e end
  return nil
end

local function setColor(e, c, a)
  if not e then return end
  pcall(function() scene:setUiColor(e, c[1], c[2], c[3], a or 1.0) end)
end

local function variant(self, st)
  st = st or STEPS[self.step]
  if not st then return nil end
  return self.padMode and st.pad or st.kb
end

-- 画面中央のポップ文字。back で膨らんで出て、少し置いて拡大しながら消える
local function pop(self, txt, col, scaleMax)
  local b = self.burstE
  if not b then return end
  scene:stopUiTweens(b)
  scene:setUiText(b, txt)
  setColor(b, col)
  scene:tweenUi(b, { alpha = 0, scale = 0.3, duration = 0.001 })
  scene:tweenUi(b, { alpha = 1, scale = scaleMax or 1.0, duration = 0.32, easing = "back" })
  time.after(0.95, function()
    if b and b:isValid() then
      scene:tweenUi(b, { alpha = 0, scale = (scaleMax or 1.0) * 1.25, duration = 0.3, easing = "in" })
    end
  end)
end

local function dotsText(step, doneUpTo)
  local out = {}
  for i = 1, #STEPS do
    if i < step or i <= (doneUpTo or 0) then
      out[#out + 1] = "[c=7CFF9E]●[/c]"
    elseif i == step then
      out[#out + 1] = "[c=55E0FF]●[/c]"
    else
      out[#out + 1] = "[c=44507A]●[/c]"
    end
  end
  return table.concat(out, " ")
end

local function setKey(cap, lbl, key)
  if not cap then return end
  if key then
    scene:tweenUi(cap, { alpha = 1, duration = 0.25 })
    if lbl then scene:setUiText(lbl, key) end
  else
    scene:tweenUi(cap, { alpha = 0, duration = 0.15 })
  end
end

-- ステップ内容をHUDへ反映する。refresh=true はデバイス切替による差し替え
-- (チェック状態は維持し、音も鳴らさない)
local function applyStep(self, i, refresh)
  local st = STEPS[i]
  local v = variant(self, st)

  if self.text then
    scene:setUiText(self.text, v.text)        -- タイプライター再スタート
    setColor(self.text, { 1, 1, 1 })
  end
  if self.dots then scene:setUiText(self.dots, dotsText(i)) end

  -- キーキャップ: 2枚 / 1枚(中央へ寄せる) / ワイド
  setKey(self.cap1, self.lbl1, v.keys[1])
  setKey(self.cap2, self.lbl2, v.keys[2])
  if self.wide then
    scene:tweenUi(self.wide, { alpha = v.wide and 1 or 0, duration = v.wide and 0.25 or 0.15 })
    if v.wide and self.lblw then scene:setUiText(self.lblw, v.wideLabel or "") end
  end
  -- dx は相対移動なので「今どこに居るか」を覚えて差分だけ動かす
  if self.cap1 then
    local want = (#v.keys == 1) and 33 or 0
    local delta = want - (self.cap1Shift or 0)
    if delta ~= 0 then scene:tweenUi(self.cap1, { dx = delta, duration = 0.2, easing = "out" }) end
    self.cap1Shift = want
  end

  -- モードアイコン(先送り=シアン時計 / まき戻し=紫時計)
  if self.iconFF then scene:tweenUi(self.iconFF, { alpha = (st.icon == "ff") and 1 or 0, duration = 0.25 }) end
  if self.iconRW then scene:tweenUi(self.iconRW, { alpha = (st.icon == "rw") and 1 or 0, duration = 0.25 }) end

  if not refresh then
    -- チェックは隠し直し、パネルをひと押しして注目させる
    if self.check then scene:tweenUi(self.check, { alpha = 0, scale = 1, duration = 0.001 }) end
    if self.panel then uifx.punch(self.panel, 1.045, 0.22) end
    audio:playSFX("audio/ui/menu_select.wav", false)
  end
end

-- 表示中の操作キー1つぶんの「いま押されているか」。ラベル表記からキーボード/パッド両対応で判定
local function labelDown(label)
  local down = false
  pcall(function()
    if label == "Lスティック" then
      local sx, sy = padStick("left")
      down = math.abs(sx) > 0.35 or math.abs(sy) > 0.35
      return
    end
    if keyDown(label) then down = true end
    if not down and padDown(label) then down = true end
  end)
  return down
end

-- 現ステップで表示中の全キーキャップのラベル一覧
local function requiredLabels(v)
  local t = {}
  if v.keys[1] then t[#t + 1] = v.keys[1] end
  if v.keys[2] then t[#t + 1] = v.keys[2] end
  if v.wide and v.wideLabel then t[#t + 1] = v.wideLabel end
  return t
end

-- 表示中の操作キーを「全部」押したか(1回ずつでよい)。押した瞬間を pressed に記録
local function allKeysPressed(self)
  local v = variant(self)
  if not v then return true end
  local ok = true
  for _, l in ipairs(requiredLabels(v)) do
    if labelDown(l) then self.pressed[l] = true end
    if not self.pressed[l] then ok = false end
  end
  return ok
end

local function showStep(self, i)
  self.step = i
  self.phase = "active"
  self.stepT = 0
  self.pressed = {}        -- このステップで押した操作キーの記録(全部押すまでクリアしない)
  self.demoT = nil         -- goalステップのシークバー実演タイマー
  self.demoPhase = nil
  self.demoN = 0
  applyStep(self, i, false)
  -- 背景のコントローラーデモ(TutPadDemo.lua)へ現ステップの操作を通知
  events:emit("tut_step", { kind = STEPS[i].kind })
end

local function complete(self)
  self.phase = "celebrate"
  self.celebT = 0
  audio:playSFX("audio/ui/menu_enter.wav", false)

  -- チェックのスタンプ(大→定位置に back で着地)+パネル白フラッシュ+振動
  local c = self.check
  if c then
    scene:stopUiTweens(c)
    scene:tweenUi(c, { alpha = 1, scale = 2.3, duration = 0.001 })
    time.after(0.03, function()
      if c and c:isValid() then scene:tweenUi(c, { scale = 1.0, duration = 0.35, easing = "back" }) end
    end)
  end
  if self.panel then
    scene:tweenUi(self.panel, { color = { 1.7, 1.7, 1.7 }, duration = 0.08 })
    time.after(0.12, function()
      if self.panel and self.panel:isValid() then
        scene:tweenUi(self.panel, { color = { 1, 1, 1 }, duration = 0.25 })
      end
    end)
    scene:tweenUi(self.panel, { shake = 5, duration = 0.3 })
  end
  if self.dots then scene:setUiText(self.dots, dotsText(self.step + 1, self.step)) end
  if self.step < #STEPS then pop(self, "STEP CLEAR!", COL.green, 1.0) end

  local p = self.player and self.player.transform.position
  if p then FX.spark(p.x, p.y + 0.9, p.z, 14, 0.49, 1.0, 0.62) end
  fx:pulse(0.12)
  padVibrate(0.4, 0.25, 0.15)
end

-- 表示中のキーキャップ/アイコンを周期的にドクンとさせて「押すのはこれ」を示す
local function pulseKeys(self)
  local v = variant(self)
  if not v then return end
  if v.keys[1] and self.cap1 then uifx.punch(self.cap1, 1.12, 0.3) end
  if v.keys[2] and self.cap2 then uifx.punch(self.cap2, 1.12, 0.3) end
  if v.wide and self.wide then uifx.punch(self.wide, 1.08, 0.3) end
  local st = STEPS[self.step]
  if st then
    if st.icon == "ff" and self.iconFF then uifx.punch(self.iconFF, 1.1, 0.3) end
    if st.icon == "rw" and self.iconRW then uifx.punch(self.iconRW, 1.1, 0.3) end
  end
end

-- 入力デバイス検出: パッド操作でパッド表示に、キーボード操作でキーボード表示に切り替える
local PAD_BTNS = { "A", "B", "X", "Y", "RB", "LB", "DPAD_LEFT", "DPAD_RIGHT", "DPAD_UP", "DPAD_DOWN", "START", "BACK" }
local KB_KEYS = { "A", "D", "W", "S", "E", "Q", "SPACE", "LEFT", "RIGHT", "UP", "DOWN", "R", "TAB" }

local function detectDevice(self)
  local padActive = false
  pcall(function()
    local sx, sy = padStick("left")
    if math.abs(sx) > 0.35 or math.abs(sy) > 0.35 then padActive = true end
    if not padActive then
      for _, b in ipairs(PAD_BTNS) do
        if padDown(b) then padActive = true break end
      end
    end
  end)
  if padActive and not self.padMode then
    self.padMode = true
    if self.step > 0 then applyStep(self, self.step, true) end
    return
  end
  if self.padMode then
    for _, k in ipairs(KB_KEYS) do
      if keyDown(k) then
        self.padMode = false
        if self.step > 0 then applyStep(self, self.step, true) end
        return
      end
    end
  end
end

-- 達成トラッカー(単調): 該当ステップより前にやってしまっても取りこぼさない
local function trackProgress(self, dt)
  local drawHeld, aimHeld, lookHeld = false, false, false
  pcall(function()
    drawHeld = keyDown("E") or padDown("RB")
    aimHeld  = keyDown("W") or keyDown("S") or keyDown("UP") or keyDown("DOWN")
    if not aimHeld then
      local sx, sy = padStick("left")
      aimHeld = math.abs(sy) > 0.35
    end
    lookHeld = keyDown("TAB") or padDown("X")
  end)
  if drawHeld then
    self.gDrawT = self.gDrawT + dt
    if aimHeld then self.gAimT = self.gAimT + dt end
  end
  if lookHeld then self.gLookT = self.gLookT + dt end
end

function OnStart(self)
  self.t = 0
  self.step = 0
  self.phase = "intro"     -- intro / active / celebrate / done
  self.celebT = 0
  self.pulseT = 0
  self.walked = 0
  self.prevX = nil
  self.cap1Shift = 0
  self.padMode = true      -- 初期表示はコントローラ。キーボード入力を検出したら自動で切替
  self.pressed = {}
  self.gDrawT = 0          -- かまえ(E/RB長押し)の累計秒
  self.gAimT = 0           -- かまえ中にねらいを動かした累計秒
  self.gLookT = 0          -- 全景(TAB/X長押し)の累計秒
  self.doorHit = false     -- 先送り矢がとびらに当たった
  self.needleHit = false   -- まき戻し矢が針山に当たった

  self.panel  = ent("TutPanel")
  self.title  = ent("TutStepTitle")   -- 旧レイアウトの見出し行。1行構成にしたので常に空
  self.text   = ent("TutStepText")
  self.sub    = ent("TutStepSub")     -- 旧ヒントカルーセル行。廃止につき常に空
  self.dots   = ent("TutDots")
  self.burstE = ent("TutBurst")
  self.check  = ent("TutCheck")
  self.cap1   = ent("TutKeyCap1")
  self.cap2   = ent("TutKeyCap2")
  self.lbl1   = ent("TutKeyLbl1")
  self.lbl2   = ent("TutKeyLbl2")
  self.wide   = ent("TutKeyWide")
  self.lblw   = ent("TutKeyLblW")
  self.iconFF = ent("TutIconFF")
  self.iconRW = ent("TutIconRW")
  self.player = ent("Player")
  self.seekBar   = ent("SeekBar")
  self.seekGhost = ent("TutSeekGhost")   -- goalステップの「端までいったらアウト」実演▼

  -- 初期状態: パネルは画面下(+140px)へ隠す。バースト/チェック/キー/アイコンは透明
  if self.panel then scene:tweenUi(self.panel, { alpha = 0, dy = 140, duration = 0.001 }) end
  for _, e in ipairs({ self.burstE, self.check, self.iconFF, self.iconRW,
                       self.cap1, self.cap2, self.wide, self.seekGhost }) do
    if e then scene:tweenUi(e, { alpha = 0, duration = 0.001 }) end
  end
  if self.title then scene:setUiText(self.title, "") end
  if self.sub then scene:setUiText(self.sub, "") end

  -- 矢ヒットの達成フラグ(単調)。完了演出は complete() 側に一本化
  events:on("time_skip", function(d)
    if d.target == "TutDoor" then self.doorHit = true end
  end)
  events:on("time_rewind", function(d)
    if d.target == "TutNeedle" then self.needleHit = true end
  end)

  events:on("stage_cleared", function()
    if self.phase == "done" then return end
    self.phase = "done"
    saveNum("ta_tutorial_done", 1)   -- 以後タイトルのSTARTはセレクト直行(title.lua が参照)
    pop(self, "チュートリアル クリア！", COL.gold, 1.25)
    if self.panel then
      scene:tweenUi(self.panel, { alpha = 0, dy = 160, duration = 0.45, easing = "in" })
    end
    if self.seekGhost then scene:tweenUi(self.seekGhost, { alpha = 0, duration = 0.15 }) end
    local p = self.player and self.player.transform.position
    if p then
      FX.spark(p.x, p.y + 1.0, p.z, 24, 1.0, 0.85, 0.3)
      FX.shockwave(p.x, p.y + 0.5, p.z, 14, 8, 1.0, 0.85, 0.3)
    end
  end)

  events:on("player_died", function()
    if self.phase ~= "done" then
      pop(self, "だいじょうぶ、もういちど！", COL.red, 1.0)
    end
  end)
end

function OnUpdate(self, dt)
  self.t = self.t + dt
  detectDevice(self)
  trackProgress(self, dt)

  -- 入場: 開幕バナーが消えてから、パネルが下から back で滑り込み → STEP 1
  if self.phase == "intro" then
    if self.t > INTRO_PANEL_AT and not self.panelIn then
      self.panelIn = true
      if self.panel then scene:tweenUi(self.panel, { alpha = 1, dy = -140, duration = 0.6, easing = "back" }) end
    end
    if self.t > INTRO_STEP1_AT then showStep(self, 1) end
    return
  end

  if self.phase == "done" then return end

  -- キーキャップの鼓動
  self.pulseT = self.pulseT + dt
  if self.pulseT > 1.05 then
    self.pulseT = 0
    if self.phase == "active" then pulseKeys(self) end
  end

  if self.phase == "celebrate" then
    self.celebT = self.celebT + dt
    if self.celebT >= CELEB_DUR then
      if self.step < #STEPS then showStep(self, self.step + 1) end
    end
    return
  end

  -- 完了判定(phase == "active"): 「表示中の操作キーを全部押した」AND「実際にその操作ができた」
  local st = STEPS[self.step]
  local p = self.player and self.player.transform.position
  if not (p and st) then return end
  self.stepT = self.stepT + dt
  local keysOk = allKeysPressed(self)
  if st.kind == "walk" then
    if self.prevX then self.walked = self.walked + math.abs(p.x - self.prevX) end
    self.prevX = p.x
    if keysOk and self.walked >= self.walkGoal then complete(self) end
  elseif st.kind == "jump" then
    if keysOk and p.x > self.jumpX then complete(self) end
  elseif st.kind == "look" then
    if keysOk and self.gLookT >= 0.7 then complete(self) end
  elseif st.kind == "draw" then
    if keysOk and self.gDrawT >= 0.6 then complete(self) end
  elseif st.kind == "aim" then
    if keysOk and self.gAimT >= 0.35 then complete(self) end
  elseif st.kind == "shoot" then
    if keysOk and self.doorHit then complete(self) end
  elseif st.kind == "rw" then
    if keysOk and self.needleHit then complete(self) end
  elseif st.kind == "goal" then
    -- シークバー実演: ▼が左端→右端へ掃引し「アウト！」(最初の2周だけ。以降は静かに)
    self.demoT = (self.demoT or 0) + dt
    local g = self.seekGhost
    if g and (self.demoN or 0) < 2 then
      if not self.demoPhase then
        self.demoPhase = "sweep"
        scene:stopUiTweens(g)
        scene:tweenUi(g, { alpha = 1, duration = 0.12 })
        scene:tweenUi(g, { dx = SCREEN_W - 48, duration = 1.5 })
      elseif self.demoPhase == "sweep" and self.demoT >= 1.55 then
        self.demoPhase = "out"
        pop(self, "アウト！", COL.red, 0.95)
        fx:pulse(0.1)
        scene:tweenUi(g, { alpha = 0, duration = 0.2 })
      elseif self.demoPhase == "out" and self.demoT >= 3.4 then
        scene:tweenUi(g, { dx = -(SCREEN_W - 48), duration = 0.001 })
        self.demoT = 0
        self.demoPhase = nil
        self.demoN = (self.demoN or 0) + 1
      end
    end
  end
  -- goal ステップは stage_cleared イベントで完了
end
