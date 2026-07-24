-- Player.lua -- 「時を先送りさせる矢」プレイヤー本体。
-- 横視点プラットフォーマー(独自の重力/移動を手書き。Joltは使わない)。カメラは固定(GameCamera側で
-- 静止設定済み、Playerは一切動かさない)。
-- 弓矢: 1本のみ所持。E(先送り/シアン) または Q(後戻り/紫) を引き絞る(移動ロック・
--        矢印キー/WASDで8方向照準・引いた秒数で量が変化)→離すと発射。パッドはX=先送り/LB=後戻り。
--        命中後0.4秒刺さって見せたあと、自動でホーミングして手元へ帰ってくる(回収操作は不要)。
--        先送り矢=対象の時間を進める(time_skip) / 後戻り矢=対象の時間を巻き戻す(time_rewind)。
-- 死亡(落下)は自分では巻き戻さず、events:emit("player_died") で GameManager に委ねる(シーン再読込で全リセット)。
--
-- 当たり判定の統一ルール: 全てのスプライトエンティティは sprite2d.size=(1,1) 固定・
-- transform.scale が実寸(=当たり判定サイズ)を兼ねる。円判定は使わず、全てtransform.scaleから
-- 半径(半幅/半高)を出すAABBで判定する(スプライトの見た目と完全一致させるため)。
properties = {
  { name = "speed",        type = "float",  default = 5.0,  min = 1,  max = 15, label = "移動速度" },
  { name = "jumpSpeed",     type = "float",  default = 11.6, min = 1,  max = 20, label = "ジャンプ初速" },
  { name = "gravity",       type = "float",  default = 40.0, min = 1,  max = 80, label = "重力加速度" },
  { name = "killY",         type = "float",  default = -4.0,                    label = "この高さより下に落ちたら死亡(奈落)" },
  { name = "halfW",         type = "float",  default = 0.4,  min = 0.1, max = 2, label = "当たり半幅(見た目より少し小さめ。手足の広がり分を除外)" },
  { name = "halfHeight",    type = "float",  default = 0.55, min = 0.1, max = 3, label = "当たり半高(scale.yの半分と合わせる/接地オフセット)" },
  { name = "arrowSpeed",    type = "float",  default = 15.0, min = 1,  max = 40, label = "矢の速度(等速直線運動)" },
  { name = "arrowRange",    type = "float",  default = 18.0, min = 1,  max = 60, label = "矢の最大飛距離" },
  { name = "arrowHalf",     type = "float",  default = 0.1,  min = 0.02,max = 1, label = "矢自体の当たり半径(先端の太さ)" },
  { name = "minSkip",       type = "float",  default = 2.0,  min = 0,  max = 20, label = "最小先送り量(軽く引いた時)" },
  { name = "maxSkip",       type = "float",  default = 8.0,  min = 0,  max = 30, label = "最大先送り量(引き絞りきった時)" },
  { name = "maxDrawTime",   type = "float",  default = 3.0,  min = 0.2, max = 8, label = "先送りの引き絞り最大秒数" },
  { name = "maxRewind",     type = "float",  default = 5.0,  min = 0,  max = 30, label = "最大後戻り量(2026-07-24: メーター後半が使われないため半減)" },
  { name = "rewindDrawTime", type = "float", default = 1.5,  min = 0.2, max = 8, label = "後戻りの引き絞り最大秒数(量が半分なのでチャージも倍速)" },
  { name = "aimTurnSpeed",  type = "float",  default = 270.0,min = 30,  max = 1080,label = "照準の旋回速度(度/秒。WASDでいきなり真上/真下にならないように)" },
  { name = "climbSpeed",    type = "float",  default = 4.0,  min = 1,  max = 12, label = "ツタを登る速度" },
  { name = "targets",       type = "string", default = "",                      label = "先送り対象(カンマ区切り)" },
  { name = "standables",    type = "string", default = "",                      label = "上からのみ乗れる一方通行足場(動く床/橋。カンマ区切り)" },
  { name = "climbables",    type = "string", default = "",                      label = "登れる蔦等(カンマ区切り)" },
  { name = "arrowStops",    type = "string", default = "",                      label = "矢が刺さって止まる地形(床/ブロック。カンマ区切り)" },
  { name = "solids",        type = "string", default = "",                      label = "全面ソリッド地形(床/壁/ブロック。上下左右すべてブロック。矢は貫通、カンマ区切り)" },
  { name = "mirrors",       type = "string", default = "",                      label = "矢を反射する鏡(カンマ区切り。rotation.zで向き=0:'/' 90:'\\')" },
  { name = "maxBounces",    type = "int",    default = 4,   min = 1,  max = 10, label = "矢が反射できる最大回数" },
  { name = "rewindShots",   type = "int",    default = 3,   min = 0,  max = 9,  label = "後戻り矢の使用可能回数(タイマー返金は強いので有限)" },
}

-- プレイヤーの表示状態を、補助スプライトの名前で一元管理する。
local PLAYER_SPRITE_NAMES = {
  idle = "PlayerIdleSprite",
  run = "PlayerRunSprite",
  jump = "PlayerJumpSprite",
  bow = "PlayerBowSprite",
}

-- 状態ごとのスプライトアニメーション設定を一つにまとめる。
local PLAYER_ANIMATION_SETTINGS = {
  idle = { frames = 0, fps = 0, cols = 0, row = 0 },
  run = { frames = 6, fps = 10, cols = 6, row = 0 },
  jump = { frames = 7, fps = 8, cols = 7, row = 0 },
  bow = { frames = 0, fps = 0, cols = 0, row = 0 },
}

local function trimSplit(csv)
  local out = {}
  for w in string.gmatch(csv or "", "[^,]+") do
    local name = w:match("^%s*(.-)%s*$")
    if name ~= "" then out[#out + 1] = name end
  end
  return out
end

-- 半幅/半高同士のAABB重なり判定(スプライトの実寸=transform.scaleに基づく)
local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

-- 巻き戻し残量HUD(アイコン1個+「×N」)。残数0でアイコンごと暗く沈める
local function refreshRewindIcons(self)
  local on = self.shotsLeft > 0
  for _, e in pairs(self.rewindIcons or {}) do
    if e and e:isValid() then
      if on then
        scene:setUiColor(e, 0.78, 0.58, 1.0, 1.0)
      else
        scene:setUiColor(e, 0.45, 0.35, 0.65, 0.25)
      end
    end
  end
  if self.rewindCountUi and self.rewindCountUi:isValid() then
    scene:setUiText(self.rewindCountUi, "×" .. self.shotsLeft)
    pcall(function()
      if on then
        scene:setUiColor(self.rewindCountUi, 0.78, 0.58, 1.0, 1.0)
      else
        scene:setUiColor(self.rewindCountUi, 0.5, 0.42, 0.68, 0.5)
      end
    end)
  end
end

function OnStart(self)
  -- オプションメニューが開いている間は操作を受け付けない(環境分離のためイベントで受ける)
  self.optionsOpen = false
  events:on("options_open",  function() self.optionsOpen = true  end)
  events:on("options_close", function() self.optionsOpen = false end)
  -- 開幕シネマ中は入力・物理ごと凍結(StageIntro.lua が発行)
  self.introOn = false
  events:on("stage_intro", function(d) self.introOn = d and d.on or false end)
  -- 横長で低い的(寝ている針山・崩れ足場など。各スクリプトが flat_target で通知):
  -- 矢判定の縦膨張(最低±0.8)を外して実寸にする=水平弾道が上を素通りできる
  self.lyingN = {}
  events:on("flat_target", function(d)
    if d and d.name then self.lyingN[d.name] = d.on end
  end)

  local p = self.transform.position
  self.startX, self.startY, self.startZ = p.x, p.y, p.z
  self.vx, self.vy = 0, 0
  self.facing = 1
  self.grounded = false
  self.climbing = false
  self.fellOnce = false

  self.hasArrow = true
  self.arrowFlying = false
  self.arrowStuck = false
  self.arrowReturning = false
  self.stuckT = 0
  self.arrowVX, self.arrowVY = 0, 0
  self.stuckX, self.stuckY = 0, 0
  self.stuckTarget = nil

  self.drawing = false
  self.drawMode = "skip"   -- "skip"(E/先送り) or "rewind"(Q/後戻り)
  self.drawT = 0
  self.aimX, self.aimY = 1, 0
  self.pendingAmount = self.minSkip
  self.pendingMode = "skip"
  self.shotsLeft = self.rewindShots
  self.lastTs = 1.0
  -- 引き絞りゲージ(時計盤HUD)。旧 DrawAmount テキストの後継(tools/inject_draw_gauge.py が配置)
  self.gaugeE     = scene:findEntity("DrawGauge")
  self.gaugeFF    = scene:findEntity("DrawGaugeArcFF")
  self.gaugeRW    = scene:findEntity("DrawGaugeArcRW")
  self.gaugeHand  = scene:findEntity("DrawGaugeHand")
  self.gaugeShown = false
  if self.gaugeE and self.gaugeE:isValid() then
    scene:tweenUi(self.gaugeE, { alpha = 0, duration = 0.001 })
  end
  -- 巻き戻し残量: アイコン1個+「×N」テキスト(gen_stages.py が生成)
  self.rewindIcons = {}
  for i = 1, 9 do
    local e = scene:findEntity("RewindIcon" .. i)
    if e and e:isValid() then self.rewindIcons[i] = e end
  end
  self.rewindCountUi = scene:findEntity("RewindCount")
  refreshRewindIcons(self)

  -- エディタで複製すると「名前 (1)」「名前 (2)」…ができる。propsのリストは基本名だけ書けば
  -- よいように、実在する "(n)" 付き複製をシーンから探して自動で同じリストに加える。
  -- (エディタ保存でprops値が古いリストへ戻っても、複製がすり抜けにならない保険)
  local function expandDuplicates(list)
    local out = {}
    for _, base in ipairs(list) do
      out[#out + 1] = base
      local miss = 0
      local i = 1
      while miss < 3 and i <= 32 do        -- 欠番(削除済み)は3連続まで許容して先を探す
        local name = base .. " (" .. i .. ")"
        local e = scene:findEntity(name)
        if e and e:isValid() then
          out[#out + 1] = name
          miss = 0
        else
          miss = miss + 1
        end
        i = i + 1
      end
    end
    return out
  end

  -- 各状態の表示用エンティティを取得し、初期状態を待機にする。
  self.playerSprites = {}
  for state, name in pairs(PLAYER_SPRITE_NAMES) do
    local sprite = scene:findEntity(name)
    if sprite and sprite:isValid() then self.playerSprites[state] = sprite end
  end
  -- Sprite2D APIへ渡すPlayer本体のEntity userdataを取得する。
  self.playerEntity = scene:findEntity("Player")
  -- 補助スプライトが1つでもあるシーンだけ素のPlayerスプライトを非表示にする
  -- (アニメ用スプライト未配置のシーンでプレイヤーが消えないための保険)
  if next(self.playerSprites) and self.playerEntity and self.playerEntity:isValid() then
    scene:setSpriteAlpha(self.playerEntity, 0.0)
  end
  self.playerVisualState = nil
  self.bowTimer = 0

  self.targetList = expandDuplicates(trimSplit(self.targets))
  self.standList  = expandDuplicates(trimSplit(self.standables))
  self.climbList  = expandDuplicates(trimSplit(self.climbables))
  self.solidList  = expandDuplicates(trimSplit(self.solids))
  self.stopList   = expandDuplicates(trimSplit(self.arrowStops))
  self.mirrorList = trimSplit(self.mirrors)
  self.bounces    = 0
  -- 乗っている足場(名前と前フレーム位置)。床が動いた分だけプレイヤーを一緒に運ぶ
  self.rideName  = nil
  self.ridePrevX = 0
  self.ridePrevY = 0

  -- ファンの気流(Fan.luaが毎フレーム送ってくる外力。適用したら消費)
  self.extAY = 0
  self.extAX = 0
  events:on("fan_force", function(data)
    self.extAY = data.ay or 0
    self.extAX = data.ax or 0
  end)

  -- 早送り中で実体のない solid(CrushWall等)。名前→残り秒。期間中は物理ブロックしない
  self.ghostSolids = {}
  events:on("solid_ghost", function(data)
    if data.target then self.ghostSolids[data.target] = data.duration or 0.35 end
  end)

  -- 矢オブジェクトは開始時は画面外(下方)に隠しておく
  local arrowE = scene:findEntity("Arrow")
  if arrowE and arrowE:isValid() then
    arrowE.transform.position = Vec3.new(0, -100, 0)
  end
end

-- 表示用スプライトをPlayer本体と同じ位置・向き・大きさへ同期する。
local function syncPlayerSpriteTransform(self)
  local transform = self.transform
  for _, sprite in pairs(self.playerSprites or {}) do
    if sprite and sprite:isValid() then
      sprite.transform.position = Vec3.new(transform.position.x, transform.position.y, transform.position.z)
      sprite.transform.rotation = Vec3.new(transform.rotation.x, transform.rotation.y, transform.rotation.z)
      sprite.transform.scale = Vec3.new(transform.scale.x, transform.scale.y, transform.scale.z)
    end
  end
end

-- 待機・走行・ジャンプ・弓の表示を切り替え、状態変更時だけ再生位置をリセットする。
local function setPlayerVisualState(self, state)
  if self.playerVisualState == state then
    syncPlayerSpriteTransform(self)
    return
  end

  self.playerVisualState = state
  local setting = PLAYER_ANIMATION_SETTINGS[state]
  for name, sprite in pairs(self.playerSprites or {}) do
    if sprite and sprite:isValid() then
      scene:setSpriteAlpha(sprite, name == state and 1.0 or 0.0)
      if name == state and setting then
        scene:setSpriteAnim(sprite, setting.frames, setting.fps, setting.cols, setting.row)
        scene:setSpriteAnimMode(sprite, 0)
      end
    end
  end
  syncPlayerSpriteTransform(self)
end

-- 物理状態と弓操作状態から、現在表示すべきプレイヤー状態を決める。
local function updatePlayerVisual(self)
  local state = "idle"
  if self.drawing or self.bowTimer > 0 then
    state = "bow"
  elseif not self.grounded or self.climbing then
    state = "jump"
  elseif math.abs(self.vx or 0) > 0.01 then
    state = "run"
  end
  setPlayerVisualState(self, state)
end

-- ghost中(CrushWallが早送りで実体を失っている間)は当たり判定から外す
local function isGhost(self, name)
  return self.ghostSolids[name] and self.ghostSolids[name] > 0
end

-- 名前リストから「有効なコライダー」を取り出す。存在しない/隠されている(y<-50)ものは除外。
local function colliderOf(self, name)
  local e = scene:findEntity(name)
  if not (e and e:isValid()) or isGhost(self, name) then return nil end
  local ep, es = e.transform.position, e.transform.scale
  if ep.y < -50 then return nil end   -- RisePlatform等の「隠れている」状態
  return ep.x, ep.y, es.x * 0.5, es.y * 0.5
end

-- X方向の解決: solids(全面ソリッド)のみ。既に食い込んでいる相手から離れる動きは許可(脱出可)。
local function resolveX(self, py, nx)
  local px = self.transform.position.x
  for _, name in ipairs(self.solidList) do
    local ex, ey, ehw, ehh = colliderOf(self, name)
    -- 0.06 のマージン: 足場の上にちょうど立っている状態(縦の重なり=0)を
    -- 「壁に埋まっている」と誤判定して横移動がロックされるのを防ぐ
    if ex and math.abs(py - ey) < (self.halfHeight + ehh - 0.06) then
      if math.abs(nx - ex) < (self.halfW + ehw) then
        local curOverlap = math.abs(px - ex) < (self.halfW + ehw)
        if curOverlap then
          -- 既に重なっている: 離れる向きだけ許可
          if math.abs(nx - ex) <= math.abs(px - ex) then nx = px end
        else
          -- 側面へ押し戻す(すり抜け防止のため座標を接地面ぴったりに置く)
          nx = (nx > ex) and (ex + ehw + self.halfW) or (ex - ehw - self.halfW)
        end
      end
    end
  end
  return nx
end

-- Y方向の解決: 下降中はsolids(上面)+standables(一方通行の上面)に着地、上昇中はsolidsの下面で頭打ち。
-- 「前フレームの足元が上面より上にあった」ときだけ着地させる=下から突き抜けて乗ることはできない。
local function resolveY(self, nx, py, ny)
  local landedTop, landedName = nil, nil
  local footPrev, footNew = py - self.halfHeight, ny - self.halfHeight
  local headPrev, headNew = py + self.halfHeight, ny + self.halfHeight

  local function tryLand(name, oneWay)
    local ex, ey, ehw, ehh = colliderOf(self, name)
    if not ex then return end
    if math.abs(nx - ex) >= (self.halfW + ehw) then return end
    local top = ey + ehh
    if self.vy <= 0 and footPrev >= top - 0.001 and footNew <= top then
      if not landedTop or top > landedTop then landedTop, landedName = top, name end
    end
    if oneWay then return end
    -- 全面ソリッドは天井としても効く
    local bot = ey - ehh
    if headPrev <= bot + 0.001 and headNew >= bot then
      ny = bot - self.halfHeight
      if self.vy > 0 then self.vy = 0 end
    end
  end

  if self.vy <= 0 then
    for _, name in ipairs(self.solidList) do tryLand(name, false) end
    for _, name in ipairs(self.standList) do tryLand(name, true) end
  else
    for _, name in ipairs(self.solidList) do tryLand(name, false) end
  end

  if landedTop then
    ny = landedTop + self.halfHeight
    self.vy = 0
    self.grounded = true
    self.rideName = landedName
  else
    self.grounded = false
    self.rideName = nil
  end
  return ny
end

-- 乗っている足場が動いた分だけプレイヤーを一緒に運ぶ(動く床から置いていかれない)
local function carryByRide(self)
  if not self.rideName then return end
  local ex, ey = colliderOf(self, self.rideName)
  if not ex then self.rideName = nil; return end
  local p = self.transform.position
  local dx, dy = ex - self.ridePrevX, ey - self.ridePrevY
  self.transform.position = Vec3.new(p.x + dx, p.y + dy, p.z)
end

-- 動く床に持ち上げられて地形へめり込んだ場合に、重なりの浅い軸へ押し出す。
-- これが無いと「壁の下に立って床で持ち上がる」だけで壁をすり抜けられてしまう。
local function unstick(self)
  for _, name in ipairs(self.solidList) do
    local ex, ey, ehw, ehh = colliderOf(self, name)
    if ex then
      local p = self.transform.position
      local ox = (self.halfW + ehw) - math.abs(p.x - ex)
      local oy = (self.halfHeight + ehh) - math.abs(p.y - ey)
      if ox > 0.0001 and oy > 0.0001 then
        if oy <= ox then
          local ny = (p.y > ey) and (p.y + oy) or (p.y - oy)
          self.transform.position = Vec3.new(p.x, ny, p.z)
          if self.vy > 0 then self.vy = 0 end
        else
          local nx = (p.x > ex) and (p.x + ox) or (p.x - ox)
          self.transform.position = Vec3.new(nx, p.y, p.z)
        end
      end
    end
  end
end

local function rememberRide(self)
  if not self.rideName then return end
  local ex, ey = colliderOf(self, self.rideName)
  if ex then self.ridePrevX, self.ridePrevY = ex, ey end
end

-- 登れる蔦(climbables)に重なっていて、かつ上下キーを押している間だけ重力を上書きしてよじ登る。
-- 蔦がまだ育っていない(scale/位置的に重ならない)間は自然に触れられない=別途の状態管理が不要。
local function updateClimb(self, dt)
  self.climbing = false
  if self.drawing then return end

  local pp = self.transform.position
  local overlapping = false
  for _, name in ipairs(self.climbList) do
    local e = scene:findEntity(name)
    if e and e:isValid() then
      local p, s = e.transform.position, e.transform.scale
      local halfW, halfH = s.x * 0.5, s.y * 0.5
      if math.abs(pp.x - p.x) <= halfW + 0.3 and math.abs(pp.y - p.y) <= halfH + self.halfHeight * 0.6 then
        overlapping = true
        break
      end
    end
  end
  if not overlapping then return end

  local up = 0
  if keyDown("UP") or keyDown("W") then up = up + 1 end
  if keyDown("DOWN") or keyDown("S") then up = up - 1 end
  if up == 0 then
    local _, sy = padStick("left")
    if math.abs(sy) > 0.25 then up = sy end
  end
  if up == 0 then return end  -- 触れてるだけなら普通に重力任せ(手を伸ばして掴んでる間だけ登る)

  self.climbing = true
  self.vx = 0
  self.vy = up * self.climbSpeed
end

local function updateMovement(self, dt)
  local move = 0
  if not self.drawing then
    if keyDown("LEFT") or keyDown("A") then move = move - 1 end
    if keyDown("RIGHT") or keyDown("D") then move = move + 1 end
    if padDown("DPAD_LEFT") then move = move - 1 end
    if padDown("DPAD_RIGHT") then move = move + 1 end
    if move == 0 then
      local sx = padStick("left")
      if math.abs(sx) > 0.2 then move = sx end
    end
  end
  if move ~= 0 then self.facing = move > 0 and 1 or -1 end
  self.vx = move * self.speed

  if not self.drawing and self.grounded and (keyPressed("SPACE") or keyPressed("UP") or keyPressed("W") or padPressed("A")) then
    self.vy = self.jumpSpeed
    self.grounded = false
    audio:playSFX("audio/se/jump.wav", false)
  end

  updateClimb(self, dt)  -- 登り中なら vx/vy をここで上書き
  if not self.climbing then
    self.vy = self.vy - self.gravity * dt
    if self.extAY ~= 0 then
      if self.extAY > 0 then
        -- 上昇気流: 重力に逆らって押し上げ(上昇速度は控えめに頭打ち=ふわっと浮く)
        self.vy = math.min(self.vy + self.extAY * dt, 7.5)
        self.grounded = false
      else
        -- 吸い込み(下向きの力)
        self.vy = math.max(self.vy + self.extAY * dt, -12.0)
      end
    end
  end
  if self.extAX ~= 0 then
    self.vx = self.vx + self.extAX * 0.2   -- 吸い込みの横引き(入力より弱い=抗える)
  end
  self.extAY = 0
  self.extAX = 0

  local p = self.transform.position
  local nx = resolveX(self, p.y, p.x + self.vx * dt)
  local ny = p.y + self.vy * dt

  if self.climbing then
    -- 登り中は重力も着地判定も無視して蔦に沿って動く(ただし壁抜けはさせない)
    self.grounded = false
    self.rideName = nil
  else
    ny = resolveY(self, nx, p.y, ny)
  end

  self.transform.position = Vec3.new(nx, ny, p.z)
  self.transform.rotation = Vec3.new(0, self.facing < 0 and 180 or 0, 0)
  rememberRide(self)

  if ny < self.killY and not self.fellOnce then
    self.fellOnce = true
    events:emit("player_died", {})
  end
end

-- 入力から「狙いたい方向」を出す(離散8方向 or アナログ)。無入力なら向いてる方。
-- これは目標角度であって、実際の照準はupdateDraw内でaimAngleを毎フレーム少しずつ
-- 近づけていく(WASDでいきなり真上/真下を向かず、だんだん回転するように)。
local function aimTargetDir(self)
  local ax, ay = 0, 0
  if keyDown("LEFT") or keyDown("A") then ax = ax - 1 end
  if keyDown("RIGHT") or keyDown("D") then ax = ax + 1 end
  if keyDown("UP") or keyDown("W") then ay = ay + 1 end
  if keyDown("DOWN") or keyDown("S") then ay = ay - 1 end
  if ax == 0 and ay == 0 then
    local sx, sy = padStick("left")
    if math.abs(sx) > 0.35 or math.abs(sy) > 0.35 then ax, ay = sx, sy end
  end
  if ax == 0 and ay == 0 then return self.facing, 0 end
  local len = math.sqrt(ax * ax + ay * ay)
  return ax / len, ay / len
end

-- モード別の引き絞りパラメータ(最大量, 満充填秒)。
-- 後戻りは最大5秒・1.5秒で満充填(2026-07-24: メーター後半が使われないため半減+倍速)
local function drawSpec(self)
  if self.drawMode == "rewind" then
    return self.maxRewind, self.rewindDrawTime
  end
  return self.maxSkip, self.maxDrawTime
end

local function fireArrow(self)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  local maxAmt, maxT = drawSpec(self)
  local amount = lerp(self.minSkip, maxAmt, clamp(self.drawT / maxT, 0, 1))
  local ax, ay = self.aimX or self.facing, self.aimY or 0
  local p = self.transform.position
  local sx, sy, sz = p.x + ax * 0.7, p.y + 0.2 + ay * 0.3, p.z
  arrowE.transform.position = Vec3.new(sx, sy, sz)
  arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(ay, ax)))
  if self.drawMode == "rewind" then
    FX.spark(sx, sy, sz, 10, 0.65, 0.4, 1.0)
  else
    FX.spark(sx, sy, sz, 10, 0.3, 0.75, 1.0)
  end
  audio:playSFX("audio/se/arrow_shot.wav", false)

  self.hasArrow = false
  self.arrowFlying = true
  self.arrowVX, self.arrowVY = ax * self.arrowSpeed, ay * self.arrowSpeed
  self.shotFromX, self.shotFromY = p.x, p.y
  self.pendingAmount = amount
  self.pendingMode = self.drawMode
  self.bounces = 0
  self.drawT = 0
  -- 発射直後も弓を短時間表示して、引き絞りから発射までの動きを途切れさせない。
  self.bowTimer = 0.2

  if self.drawMode == "rewind" then
    self.shotsLeft = self.shotsLeft - 1
    refreshRewindIcons(self)
  end
end

-- 飛翔中の矢が鏡(mirrors)に重なっていれば反射する(消費せず飛び続ける)。
-- 鏡のrotation.zが90度付近="\"向き、それ以外(既定0度)="/"向きとして扱う。
-- 反射したら true を返す(この関数を呼んだ側は今フレームの他の当たり判定をスキップする)。
local function tryReflect(self, arrowE, nx, ny)
  if self.bounces >= self.maxBounces then return false end
  for _, name in ipairs(self.mirrorList) do
    local m = scene:findEntity(name)
    if m and m:isValid() then
      local mp, ms = m.transform.position, m.transform.scale
      if overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf, mp.x, mp.y, ms.x * 0.5, ms.y * 0.5) then
        local rz = m.transform.rotation.z % 180
        local backslash = rz > 45 and rz < 135
        if backslash then
          self.arrowVX, self.arrowVY = -self.arrowVY, -self.arrowVX
        else
          self.arrowVX, self.arrowVY = self.arrowVY, self.arrowVX
        end
        self.bounces = self.bounces + 1
        -- 同じ鏡へ連続ヒットしないよう、反射後の進行方向へ少し押し出す
        local px = nx + (self.arrowVX > 0 and 1 or -1) * 0.15
        local py = ny + (self.arrowVY > 0 and 1 or -1) * 0.15
        arrowE.transform.position = Vec3.new(px, py, mp.z)
        arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(self.arrowVY, self.arrowVX)))
        FX.spark(nx, ny, mp.z, 10, 0.6, 0.9, 1.0)
        fx:pulse(0.1)
        return true
      end
    end
  end
  return false
end

-- 引き絞り(E長押し): 移動ロック・矢印キー/WASDで8方向照準・離すと発射
local function updateDraw(self, dt)
  -- パッド: R1(RB)/R2(RT)=先送り, L1(LB)/L2(LT)=後戻り(トリガー未対応環境でも安全に)
  local function padHeld(n)
    local ok, v = pcall(padDown, n)
    return ok and v
  end
  local skipHeld = keyDown("E") or padHeld("RB") or padHeld("RT")
  local rwHeld = keyDown("Q") or padHeld("LB") or padHeld("LT")
  local canDraw = self.hasArrow and not self.arrowFlying and not self.arrowStuck

  -- 後戻り矢は残数制(切れたら引けない)
  if rwHeld and not self.drawing and self.shotsLeft <= 0 then
    rwHeld = false
  end

  -- 引き始めたモードを保持(引いてる最中にもう片方を押しても切り替わらない)
  local drawHeld
  if self.drawing then
    drawHeld = (self.drawMode == "rewind") and rwHeld or skipHeld
  else
    drawHeld = skipHeld or rwHeld
  end

  if drawHeld and canDraw then
    if not self.drawing then
      self.drawing = true
      self.drawMode = skipHeld and "skip" or "rewind"
      self.drawT = 0
      self.aimAngle = math.deg(math.atan(self.aimY or 0, self.aimX or self.facing))
      -- キーボード用: (左右の向き, 仰角)に分解し10度刻みに丸める
      local a0 = (self.aimAngle + 180) % 360 - 180
      self.aimSide = (math.abs(a0) <= 90) and 1 or -1
      local elev = (self.aimSide > 0) and a0 or ((a0 >= 0) and (180 - a0) or (-180 - a0))
      self.aimElev = clamp(math.floor(elev / 10 + 0.5) * 10, -90, 90)
      self.stepRepeatT = 0
    end
    local maxAmt, maxT = drawSpec(self)
    self.drawT = math.min(self.drawT + dt, maxT)

    -- 照準: パッド=スティックへなめらか追従(感度=aimTurnSpeed、低め) /
    --        キーボード=矢印(またはWASD)で10度刻みのステップ選択
    local stkX, stkY = padStick("left")
    if math.abs(stkX) > 0.35 or math.abs(stkY) > 0.35 then
      local targetAngle = math.deg(math.atan(stkY, stkX))
      local delta = angleDelta(self.aimAngle, targetAngle)
      local maxStep = self.aimTurnSpeed * dt
      self.aimAngle = self.aimAngle + clamp(delta, -maxStep, maxStep)
      -- 分解表現も追従させておく(パッド→キーボード持ち替え対策)
      local a0 = (self.aimAngle + 180) % 360 - 180
      self.aimSide = (math.abs(a0) <= 90) and 1 or -1
      self.aimElev = clamp((self.aimSide > 0) and a0 or ((a0 >= 0) and (180 - a0) or (-180 - a0)), -90, 90)
    else
      -- 10度刻み: 押した瞬間に1段、押しっぱなしで0.35秒後からリピート
      local function stepInput(up, down)
        local dir = 0
        if keyPressed(up) then dir = 1
        elseif keyPressed(down) then dir = -1 end
        if dir ~= 0 then
          self.stepRepeatT = 0.35
          return dir
        end
        if keyDown(up) or keyDown(down) then
          self.stepRepeatT = (self.stepRepeatT or 0) - dt
          if self.stepRepeatT <= 0 then
            self.stepRepeatT = 0.11
            return keyDown(up) and 1 or -1
          end
        end
        return 0
      end
      local d1 = stepInput("UP", "DOWN")
      local d2 = (d1 == 0) and stepInput("W", "S") or 0
      local step = (d1 ~= 0) and d1 or d2
      if step ~= 0 then
        self.aimElev = clamp((self.aimElev or 0) + step * 10, -90, 90)
      end
      if keyPressed("LEFT") or keyPressed("A") then self.aimSide = -1 end
      if keyPressed("RIGHT") or keyPressed("D") then self.aimSide = 1 end
      self.aimAngle = (self.aimSide or 1) > 0 and self.aimElev or (180 - self.aimElev)
    end
    local rad = math.rad(self.aimAngle)
    local ax, ay = math.cos(rad), math.sin(rad)
    self.aimX, self.aimY = ax, ay

    local amount = lerp(self.minSkip, maxAmt, clamp(self.drawT / maxT, 0, 1))
    -- 引き絞りゲージ(時計盤): 扇形が引き絞りに応じて満ち、針が回る。
    -- 先送り=シアン/時計回り、まき戻し=紫/反時計回り(針も逆回転)
    if self.gaugeE and self.gaugeE:isValid() then
      local gfrac = clamp(self.drawT / maxT, 0, 1)
      if not self.gaugeShown then
        self.gaugeShown = true
        scene:stopUiTweens(self.gaugeE)
        scene:tweenUi(self.gaugeE, { alpha = 0, scale = 0.55, duration = 0.001 })
        scene:tweenUi(self.gaugeE, { alpha = 1, scale = 1.0, duration = 0.22, easing = "back" })
      end
      local rw = (self.drawMode == "rewind")
      if self.gaugeFF and self.gaugeFF:isValid() then
        scene:setUiFill(self.gaugeFF, rw and 0 or gfrac)
      end
      if self.gaugeRW and self.gaugeRW:isValid() then
        scene:setUiFill(self.gaugeRW, rw and gfrac or 0)
      end
      if self.gaugeHand and self.gaugeHand:isValid() then
        scene:setUiRotation(self.gaugeHand, (rw and -1 or 1) * gfrac * 350.0)
        pcall(function()
          if rw then scene:setUiColor(self.gaugeHand, 0.85, 0.7, 1.0, 1.0)
          else scene:setUiColor(self.gaugeHand, 0.75, 0.95, 1.0, 1.0) end
        end)
      end
    end

    local p = self.transform.position
    local frac = self.drawT / maxT
    local len = 1.1 + 2.3 * frac
    if self.drawMode == "rewind" then
      -- 後戻り矢: 紫のビーム
      FX.beam(p.x, p.y + 0.2, p.z, p.x + ax * len, p.y + 0.2 + ay * len, p.z,
              0.6 + 0.15 * frac, 0.35 + 0.15 * frac, 1.0, 0.1, "energy", 3 + frac * 3)
    else
      -- 先送り矢: シアンのビーム
      FX.beam(p.x, p.y + 0.2, p.z, p.x + ax * len, p.y + 0.2 + ay * len, p.z,
              0.4 + 0.4 * frac, 0.75 + 0.2 * frac, 1.0, 0.1, "energy", 3 + frac * 3)
    end

    -- 軌道レーダー: 発射線を途切れない実線ビームとして毎フレーム描く。
    -- 当たり候補/地形は先に座標をまとめて取り(毎ステップ findEntity しない)、
    -- 細かい歩幅(0.25)で到達点を求めて 発射点→到達点 を1本のビームで結ぶ。
    local rx, ry = p.x + ax * 0.7, p.y + 0.2 + ay * 0.3
    local cands, stops = {}, {}
    for _, name in ipairs(self.targetList) do
      local tE = scene:findEntity(name)
      if tE and tE:isValid() then
        local tp, ts2 = tE.transform.position, tE.transform.scale
        if tp.y > -50 then
          local hh = self.lyingN[name] and ts2.y * 0.5 or math.max(ts2.y * 0.5, 0.8)
          cands[#cands + 1] = { name = name, x = tp.x, y = tp.y,
                                hw = math.max(ts2.x * 0.5, 0.8),
                                hh = hh,
                                h = math.max(ts2.y, 1.2) }
        end
      end
    end
    for _, name in ipairs(self.stopList) do
      local tE = scene:findEntity(name)
      if tE and tE:isValid() then
        local tp, ts2 = tE.transform.position, tE.transform.scale
        if tp.y > -50 then
          stops[#stops + 1] = { x = tp.x, y = tp.y, hw = ts2.x * 0.5, hh = ts2.y * 0.5 }
        end
      end
    end
    local hit, endD = nil, self.arrowRange
    local d = 0.3
    while d < self.arrowRange do
      local sx2, sy2 = rx + ax * d, ry + ay * d
      for _, c in ipairs(cands) do
        if overlapAABB(sx2, sy2, 0.05, 0.05, c.x, c.y, c.hw, c.hh) then
          hit = c
          break
        end
      end
      if hit then endD = d; break end
      local blocked = false
      for _, c in ipairs(stops) do
        if overlapAABB(sx2, sy2, 0.05, 0.05, c.x, c.y, c.hw, c.hh) then
          blocked = true
          break
        end
      end
      if blocked then endD = d; break end
      d = d + 0.25
    end
    local ex2, ey2 = rx + ax * endD, ry + ay * endD
    local cr, cg, cb
    if self.drawMode == "rewind" then cr, cg, cb = 0.62, 0.4, 1.0
    else cr, cg, cb = 0.35, 0.8, 1.0 end
    -- 本線(モード色)+細い白コア=どんな背景でも読める二重線
    FX.beam(rx, ry, p.z, ex2, ey2, p.z, cr, cg, cb, 0.06, "energy", 2.6)
    FX.beam(rx, ry, p.z, ex2, ey2, p.z, 1.0, 1.0, 1.0, 0.06, "energy", 1.0)
    -- 終端マーカー: 進行方向と直交する短い横棒(当たる場所を明示)
    local pxp, pyp = -ay, ax
    FX.beam(ex2 - pxp * 0.35, ey2 - pyp * 0.35, p.z,
            ex2 + pxp * 0.35, ey2 + pyp * 0.35, p.z, cr, cg, cb, 0.06, "energy", 3)
    -- 終端のパルスリング(0.25秒おき。的に当たる時は大きく)
    self.pulseT = (self.pulseT or 0) + dt
    if self.pulseT > 0.25 then
      self.pulseT = 0
      FX.shockwave(ex2, ey2, p.z, hit and 6 or 3, hit and 4 or 2.5, cr, cg, cb)
    end
    if hit then
      -- 対象の点滅(aim_preview)と効果量ゲージは従来の0.05秒間隔で
      self.scanT = (self.scanT or 0) + dt
      if self.scanT > 0.05 then
        self.scanT = 0
        events:emit("aim_preview", { target = hit.name, mode = self.drawMode })
        local gh = 0.4 + 2.2 * clamp((amount - self.minSkip) / (maxAmt - self.minSkip), 0, 1)
        local gx = hit.x - 1.3
        local gy = hit.y - hit.h * 0.5
        FX.beam(gx, gy, p.z, gx, gy + gh, p.z, cr, cg, cb, 0.14, "energy", 5)
      end
    end
  elseif self.drawing then
    self.drawing = false
    fireArrow(self)
    if self.gaugeShown then
      self.gaugeShown = false
      if self.gaugeE and self.gaugeE:isValid() then
        scene:stopUiTweens(self.gaugeE)
        scene:tweenUi(self.gaugeE, { alpha = 0, scale = 1.25, duration = 0.16, easing = "in" })
      end
    end
  end
end

local function stickArrow(self, arrowE, hitTargetName)
  local ap = arrowE.transform.position
  self.arrowFlying = false
  self.arrowStuck = true
  self.stuckT = 0
  self.stuckX, self.stuckY = ap.x, ap.y
  self.stuckTarget = hitTargetName
  if hitTargetName then
    if self.pendingMode == "rewind" then
      events:emit("time_rewind", { target = hitTargetName, amount = self.pendingAmount })
      FX.shockwave(ap.x, ap.y, ap.z, 12, 7, 0.65, 0.4, 1.0)
    else
      events:emit("time_skip", { target = hitTargetName, amount = self.pendingAmount })
      FX.shockwave(ap.x, ap.y, ap.z, 12, 7, 0.3, 0.75, 1.0)
    end
    fx:pulse(0.18)
    padVibrate(0.5, 0.3, 0.12)
    audio:playSpatial("audio/se/arrow_hit.wav", ap.x, ap.y, ap.z, 3, 26, 1.0)  -- 刺さってビーンと振動(刺さった場所から)
  else
    -- 地形・障害物に刺さった(的ではない)
    audio:playSpatial("audio/se/arrow_stick.wav", ap.x, ap.y, ap.z, 3, 26, 1.0)
  end
end

local function updateArrow(self, dt)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  if self.arrowFlying then
    local ap = arrowE.transform.position
    local nx, ny = ap.x + self.arrowVX * dt, ap.y + self.arrowVY * dt
    arrowE.transform.position = Vec3.new(nx, ny, ap.z)
    if self.pendingMode == "rewind" then
      FX.trail(nx, ny, ap.z, 0.65, 0.4, 1.0)
    else
      FX.trail(nx, ny, ap.z, 0.3, 0.75, 1.0)
    end

    if tryReflect(self, arrowE, nx, ny) then return end

    local hitName = nil
    for _, name in ipairs(self.targetList) do
      local t = scene:findEntity(name)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        -- 的の判定は最低でも半幅/半高0.8を保証(薄い足場や小型ギミックも狙いやすく)。
        -- ただし寝ている針山は縦を実寸に(水平弾道が上を素通りできる)
        local hh = self.lyingN[name] and ts.y * 0.5 or math.max(ts.y * 0.5, 0.8)
        if overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf, tp.x, tp.y,
                       math.max(ts.x * 0.5, 0.8), hh) then
          hitName = name
          break
        end
      end
    end

    -- 地形(arrowStops)に当たったらその手前で刺さる。床が無い所は素通りして落ちていく
    local hitTerrain = false
    for _, name in ipairs(self.stopList) do
      local t = scene:findEntity(name)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        if tp.y > -50 and overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf,
                                      tp.x, tp.y, ts.x * 0.5, ts.y * 0.5) then
          hitTerrain = true
          break
        end
      end
    end

    local travelled = (nx - self.shotFromX) * (nx - self.shotFromX) + (ny - self.shotFromY) * (ny - self.shotFromY)
    if hitName then
      stickArrow(self, arrowE, hitName)
    elseif hitTerrain then
      -- めり込んだ分だけ戻して地形の表面に刺す
      arrowE.transform.position = Vec3.new(nx - self.arrowVX * dt * 0.5, ny - self.arrowVY * dt * 0.5, ap.z)
      stickArrow(self, arrowE, nil)
    elseif ny < self.killY then
      -- 奈落へ落ちた矢もそのまま手元へ帰ってくる(ロストなし)
      self.arrowFlying = false
      self.arrowReturning = true
    elseif travelled > self.arrowRange * self.arrowRange then
      stickArrow(self, arrowE, nil)
    end
    return
  end

  if self.arrowStuck then
    -- 刺さった演出(0.4秒)だけ見せてから自動で帰還を始める。的が動けば矢も追従表示
    self.stuckT = self.stuckT + dt
    if self.stuckTarget then
      local t = scene:findEntity(self.stuckTarget)
      if t and t:isValid() then
        local tp = t.transform.position
        arrowE.transform.position = Vec3.new(tp.x, tp.y, tp.z - 0.05)
      end
    end
    if self.stuckT > 0.4 then
      self.arrowStuck = false
      self.arrowReturning = true
      self.stuckTarget = nil
    end
    return
  end

  if self.arrowReturning then
    -- ホーミングで手元へ飛んで帰ってくる(仕様書「矢は0.5秒で帰ってくる」)
    local p = self.transform.position
    local ap = arrowE.transform.position
    local dx, dy = p.x - ap.x, (p.y + 0.2) - ap.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.6 then
      self.arrowReturning = false
      self.hasArrow = true
      arrowE.transform.position = Vec3.new(0, -100, 0)
      FX.spark(p.x, p.y + 0.2, p.z, 6, 0.9, 0.9, 1.0)
    else
      local step = 30 * dt / dist
      arrowE.transform.position = Vec3.new(ap.x + dx * step, ap.y + dy * step, ap.z)
      arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(dy, dx)))
      if self.pendingMode == "rewind" then
        FX.trail(ap.x, ap.y, ap.z, 0.65, 0.4, 1.0)
      else
        FX.trail(ap.x, ap.y, ap.z, 0.3, 0.75, 1.0)
      end
    end
  end
end

function OnUpdate(self, dt)
  if self.optionsOpen then return end   -- ポーズ中は入力ごと止める
  if self.introOn then return end       -- 開幕シネマ中: StageIntro.lua が世界を凍結している
  -- 弓の発射表示時間を減らし、0未満にはしない。
  self.bowTimer = math.max(0, (self.bowTimer or 0) - dt)
  for name, t in pairs(self.ghostSolids) do
    self.ghostSolids[name] = t - dt
  end
  carryByRide(self)
  unstick(self)
  updateMovement(self, dt)
  updateDraw(self, dt)
  updateArrow(self, dt)
  updatePlayerVisual(self)

  -- 弓を構えている間、世界は0.25倍速。スクリプト環境は分離されているので
  -- グローバル変数ではなくイベントで全ギミック+GameManagerへ配る(変化時のみ発行)
  local ts = self.drawing and 0.25 or 1.0
  if ts ~= self.lastTs then
    self.lastTs = ts
    events:emit("time_scale", { scale = ts })
    -- スローモ入り: 溜め音の間BGMは止め、鳴り終わったらスローBGMで再開。解除で通常復帰
    -- (setBGMRate はエンジン新API。旧ビルドでも構え自体は動くよう pcall)
    if ts < 1.0 then
      audio:playSFX("audio/se/slowmo.wav", false)
      audio:pauseBGM()
      self.slowBgmT = 1.4   -- slowmo.wav(1.5s)のフェード尻に少し重ねてスローBGMへ繋ぐ
    else
      self.slowBgmT = nil
      pcall(function() audio:setBGMRate(1.0) end)
      audio:resumeBGM()
    end
  end
  -- 3Dサウンドのリスナーをプレイヤー位置に(右のギミックは右から鳴る)
  pcall(function()
    local lp = self.transform.position
    audio:setListener(lp.x, lp.y, lp.z)
  end)

  -- 溜め音が鳴り終わったら、遅く低いBGMをそっと戻す
  if self.slowBgmT then
    self.slowBgmT = self.slowBgmT - dt
    if self.slowBgmT <= 0 then
      self.slowBgmT = nil
      pcall(function() audio:setBGMRate(0.55) end)
      audio:resumeBGM()
    end
  end

  -- ESC/START はオプションメニュー(OptionsMenu.lua)が取る。タイトルへ戻る旧ショートカットは廃止
end
