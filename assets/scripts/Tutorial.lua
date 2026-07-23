-- Tutorial.lua -- stage0 チュートリアルの進行役。空エンティティ(TutorialDirector)に付ける。
-- 実プレイしながら6ステップ(移動→ジャンプ→時間のルール→先送り矢→まき戻し矢→ゴール)を教える。
-- 操作/ルールの詳細はサブ行の「ヒントカルーセル」(数秒ごとにフェードで差し替え)で全部見せる。
-- 入力デバイスを毎フレーム検出し、キーボード⇔ゲームパッドで説明とキー表示を自動で切り替える
-- (パッド: 移動=Lスティック / ジャンプ=A / 先送り=RB / まき戻し=LB / 全景=X / リトライ=BACK)。
-- HUD側は gen_stages.py が stage0 にだけ生成する専用エンティティ群を操作する:
--   TutPanel(下部パネル) > TutStepTitle / TutStepText(タイプライター) / TutStepSub(カルーセル) /
--   TutKeyCap1,2 (+子ラベル) / TutKeyWide(+子ラベル) / TutIconFF / TutIconRW / TutCheck / TutDots
--   TutBurst(画面中央のポップ文字、HudCanvas直下)
-- 完了判定は「実際にできたか」: 歩行距離 / 段差の先のX / 門の先のX / 針山の先のX / stage_cleared。
-- X判定は単調(戻っても達成は消えない)なので、演出中に先へ進まれても取りこぼさない。
-- ⚠ このエンジンの tweenUi の dx/dy は「相対移動」(実レイアウトを動かす)。絶対座標指定ではないので
--   出し入れは +140 → -140 のように往復で書く。
properties = {
  { name = "walkGoal", type = "float", default = 2.5,  label = "STEP1: 必要な歩行距離" },
  { name = "jumpX",    type = "float", default = 12.8, label = "STEP2: 段差を越えたと見なすX" },
  { name = "doorX",    type = "float", default = 18.5, label = "先送り矢STEP: 門のX(+1.0で通過)" },
  { name = "needleX",  type = "float", default = 27.0, label = "まき戻しSTEP: 針山のX(+1.0で通過)" },
}

local COL = {
  gold   = { 1.0, 0.85, 0.30 },
  cyan   = { 0.33, 0.88, 1.0 },
  purple = { 0.80, 0.60, 1.0 },
  green  = { 0.49, 1.0, 0.62 },
  red    = { 1.0, 0.45, 0.4 },
}

-- kind: 完了条件の種類 / autoT: 秒数経過で自動クリア / icon: パネル左の時計アイコン
-- kb / pad: 入力デバイス別の表示(text=メイン行, hints=サブ行カルーセル,
--            keys=四角キーキャップ(最大2), wide=横長キャップ, wideLabel=その文字)
local STEPS = {
  { kind = "walk", title = "STEP 1 ／ いどう", tcol = COL.gold,
    kb = { text = "[c=55E0FF]A[/c] / [c=55E0FF]D[/c] で 左右に うごこう！",
           hints = { "やじるしキー でも うごける",
                     "R キー: いつでも さいしょから やりなおし" },
           keys = { "A", "D" } },
    pad = { text = "[c=55E0FF]Lスティック[/c] で 左右に うごこう！",
            hints = { "十字キー でも うごける",
                      "BACK ボタン: さいしょから やりなおし" },
            keys = {}, wide = true, wideLabel = "Lスティック" } },
  { kind = "jump", title = "STEP 2 ／ ジャンプ", tcol = COL.gold,
    kb = { text = "[c=FFD866]SPACE[/c] で だんさを とびこえろ！",
           hints = { "W や ↑ でも とべる" },
           keys = {}, wide = true, wideLabel = "SPACE" },
    pad = { text = "[c=FFD866]A ボタン[/c] で だんさを とびこえろ！",
            hints = { "だんさの 上へ とびのろう" },
            keys = { "A" } } },
  { kind = "rules", title = "STEP 3 ／ 時間のルール", tcol = COL.gold, autoT = 10.5,
    kb = { text = "この世界では [c=FFD866]時間が ぶき[/c] だ！",
           hints = { "下の [c=FF6655]赤いバー[/c] が のこり時間。0 で しっぱい",
                     "もっている 矢で モノの時間を あやつれる",
                     "[c=55E0FF]TAB[/c] ながおしで ステージ全体を みわたせる" },
           keys = {} },
    pad = { text = "この世界では [c=FFD866]時間が ぶき[/c] だ！",
            hints = { "下の [c=FF6655]赤いバー[/c] が のこり時間。0 で しっぱい",
                      "もっている 矢で モノの時間を あやつれる",
                      "[c=55E0FF]X ボタン[/c] ながおしで ステージ全体を みわたせる" },
            keys = {} } },
  { kind = "ff", title = "STEP 4 ／ 先おくりの矢", tcol = COL.cyan, icon = "ff",
    kb = { text = "[c=55E0FF]E[/c] ながおしで ため → はなすと 発射！",
           hints = { "とびらの [c=55E0FF]時間を すすめて[/c] あけろ！",
                     "ためるほど つよい (+2 〜 +10秒)",
                     "かまえ中は 世界が [c=55E0FF]スロー[/c] に なる",
                     "かまえたまま W / S (↑↓) で ねらいを かえる",
                     "先おくりは [c=FF6655]のこり時間を すこし つかう[/c]",
                     "矢は じどうで 手もとに かえってくる" },
           keys = { "E" } },
    pad = { text = "[c=55E0FF]RB[/c] ながおしで ため → はなすと 発射！",
            hints = { "とびらの [c=55E0FF]時間を すすめて[/c] あけろ！",
                      "ためるほど つよい (+2 〜 +10秒)",
                      "かまえ中は 世界が [c=55E0FF]スロー[/c] に なる",
                      "かまえたまま Lスティックで ねらいを かえる",
                      "先おくりは [c=FF6655]のこり時間を すこし つかう[/c]",
                      "矢は じどうで 手もとに かえってくる" },
            keys = { "RB" } } },
  { kind = "rw", title = "STEP 5 ／ まき戻しの矢", tcol = COL.purple, icon = "rw",
    kb = { text = "[c=CC99FF]Q[/c] ながおしで まき戻しの矢！",
           hints = { "針山の [c=CC99FF]時間を もどして[/c] ねかせろ！",
                     "まき戻しの矢は [c=CC99FF]回数制[/c] (左上の ×のこり)",
                     "あてると [c=7CFF9E]のこり時間が すこし もどる[/c]",
                     "ねかせた針山は 時間がたつと また おきあがる" },
           keys = { "Q" } },
    pad = { text = "[c=CC99FF]LB[/c] ながおしで まき戻しの矢！",
            hints = { "針山の [c=CC99FF]時間を もどして[/c] ねかせろ！",
                      "まき戻しの矢は [c=CC99FF]回数制[/c] (左上の ×のこり)",
                      "あてると [c=7CFF9E]のこり時間が すこし もどる[/c]",
                      "ねかせた針山は 時間がたつと また おきあがる" },
            keys = { "LB" } } },
  { kind = "goal", title = "STEP 6 ／ ゴール", tcol = COL.green,
    kb = { text = "とけいが 0 に なるまえに [c=7CFF9E]ゴール[/c]！",
           hints = { "これで きほんは バッチリ！",
                     "本番ステージでは 時間との しょうぶ だ！" },
           keys = {} },
    pad = { text = "とけいが 0 に なるまえに [c=7CFF9E]ゴール[/c]！",
            hints = { "これで きほんは バッチリ！",
                      "本番ステージでは 時間との しょうぶ だ！" },
            keys = {} } },
}

local HINT_PERIOD = 3.4

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

-- サブ行のヒントを入れ替える(フェードアウト→差し替え→フェードイン)
local function setHint(self, idx, instant)
  local v = variant(self)
  if not (v and self.sub) then return end
  local n = #v.hints
  if n == 0 then scene:setUiText(self.sub, "") return end
  local txt = v.hints[((idx - 1) % n) + 1]
  if instant then
    scene:setUiText(self.sub, txt)
    return
  end
  local sub = self.sub
  scene:tweenUi(sub, { alpha = 0, duration = 0.18, easing = "in",
    onComplete = function()
      if sub and sub:isValid() then
        scene:setUiText(sub, txt)
        scene:tweenUi(sub, { alpha = 1, duration = 0.22, easing = "out" })
      end
    end })
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
-- (タイマーやチェック状態は維持し、音も鳴らさない)
local function applyStep(self, i, refresh)
  local st = STEPS[i]
  local v = variant(self, st)

  if self.title then
    scene:setUiText(self.title, st.title)
    setColor(self.title, st.tcol)
  end
  if self.text then scene:setUiText(self.text, v.text) end        -- タイプライター再スタート
  setHint(self, self.hintI or 1, true)
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

local function showStep(self, i)
  self.step = i
  self.phase = "active"
  self.stepT = 0
  self.hintI = 1
  self.hintT = 0
  applyStep(self, i, false)
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

function OnStart(self)
  self.t = 0
  self.step = 0
  self.phase = "intro"     -- intro / active / celebrate / done
  self.celebT = 0
  self.pulseT = 0
  self.walked = 0
  self.prevX = nil
  self.cap1Shift = 0
  self.padMode = false

  self.panel  = ent("TutPanel")
  self.title  = ent("TutStepTitle")
  self.text   = ent("TutStepText")
  self.sub    = ent("TutStepSub")
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

  -- 初期状態: パネルは画面下(+140px)へ隠す。バースト/チェック/キー/アイコンは透明
  if self.panel then scene:tweenUi(self.panel, { alpha = 0, dy = 140, duration = 0.001 }) end
  for _, e in ipairs({ self.burstE, self.check, self.iconFF, self.iconRW,
                       self.cap1, self.cap2, self.wide }) do
    if e then scene:tweenUi(e, { alpha = 0, duration = 0.001 }) end
  end

  -- 矢が的に当たった瞬間の「ほめ」ポップ(該当ステップ中のみ)
  events:on("time_skip", function(d)
    if d.target == "TutDoor" and (STEPS[self.step] or {}).kind == "ff" then
      pop(self, "ナイスショット！", COL.cyan, 0.9)
    end
  end)
  events:on("time_rewind", function(d)
    if d.target == "TutNeedle" and (STEPS[self.step] or {}).kind == "rw" then
      pop(self, "その調子！", COL.purple, 0.9)
    end
  end)

  events:on("stage_cleared", function()
    if self.phase == "done" then return end
    self.phase = "done"
    saveNum("ta_tutorial_done", 1)   -- 以後タイトルのSTARTはセレクト直行(title.lua が参照)
    pop(self, "チュートリアル クリア！", COL.gold, 1.25)
    if self.panel then
      scene:tweenUi(self.panel, { alpha = 0, dy = 160, duration = 0.45, easing = "in" })
    end
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

  -- 入場: パネルが下から back で滑り込み(dyは相対なので -140 で戻す)、少し置いて STEP 1
  if self.phase == "intro" then
    if self.t > 0.35 and not self.panelIn then
      self.panelIn = true
      if self.panel then scene:tweenUi(self.panel, { alpha = 1, dy = -140, duration = 0.6, easing = "back" }) end
    end
    if self.t > 1.0 then showStep(self, 1) end
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
    if self.celebT >= 1.15 then
      if self.step < #STEPS then showStep(self, self.step + 1) end
    end
    return
  end

  -- ヒントカルーセル(サブ行を数秒ごとに差し替え)
  local v = variant(self)
  local st = STEPS[self.step]
  self.stepT = self.stepT + dt
  if v and #v.hints > 1 then
    self.hintT = self.hintT + dt
    if self.hintT >= HINT_PERIOD then
      self.hintT = 0
      self.hintI = (self.hintI or 1) + 1
      setHint(self, self.hintI)
    end
  end

  -- 完了判定(phase == "active")
  local p = self.player and self.player.transform.position
  if not (p and st) then return end
  if st.kind == "walk" then
    if self.prevX then self.walked = self.walked + math.abs(p.x - self.prevX) end
    self.prevX = p.x
    if self.walked >= self.walkGoal then complete(self) end
  elseif st.kind == "jump" then
    if p.x > self.jumpX then complete(self) end
  elseif st.kind == "rules" then
    if self.stepT >= (st.autoT or 8.0) then complete(self) end
  elseif st.kind == "ff" then
    if p.x > self.doorX + 1.0 then complete(self) end
  elseif st.kind == "rw" then
    if p.x > self.needleX + 1.0 then complete(self) end
  end
  -- goal ステップは stage_cleared イベントで完了
end
