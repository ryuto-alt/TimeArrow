-- Player.lua -- 「時を先送りさせる矢」プレイヤー本体。
-- 横視点プラットフォーマー(独自の重力/移動を手書き。Joltは使わない)。カメラは固定(GameCamera側で
-- 静止設定済み、Playerは一切動かさない)。
-- 弓矢: 1本のみ所持。Eを引き絞る(移動ロック・矢印キー/WASDで8方向照準・引いた秒数でスキップ量が変化)→
--        離すと発射。刺さったオブジェクトに触れる(=矢が刺さった"その場"に触れる)ことで回収できる。
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
  { name = "maxSkip",       type = "float",  default = 10.0, min = 0,  max = 30, label = "最大先送り量(引き絞りきった時)" },
  { name = "maxDrawTime",   type = "float",  default = 3.0,  min = 0.2, max = 8, label = "引き絞り最大秒数" },
  { name = "aimTurnSpeed",  type = "float",  default = 270.0,min = 30,  max = 1080,label = "照準の旋回速度(度/秒。WASDでいきなり真上/真下にならないように)" },
  { name = "climbSpeed",    type = "float",  default = 4.0,  min = 1,  max = 12, label = "ツタを登る速度" },
  { name = "targets",       type = "string", default = "",                      label = "先送り対象(カンマ区切り)" },
  { name = "standables",    type = "string", default = "",                      label = "上からのみ乗れる一方通行足場(動く床/橋。カンマ区切り)" },
  { name = "climbables",    type = "string", default = "",                      label = "登れる蔦等(カンマ区切り)" },
  { name = "arrowStops",    type = "string", default = "",                      label = "矢が刺さって止まる地形(床/ブロック。カンマ区切り)" },
  { name = "solids",        type = "string", default = "",                      label = "全面ソリッド地形(床/壁/ブロック。上下左右すべてブロック。矢は貫通、カンマ区切り)" },
  { name = "mirrors",       type = "string", default = "",                      label = "矢を反射する鏡(カンマ区切り。rotation.zで向き=0:'/' 90:'\\')" },
  { name = "maxBounces",    type = "int",    default = 4,   min = 1,  max = 10, label = "矢が反射できる最大回数" },
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

function OnStart(self)
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
  self.arrowVX, self.arrowVY = 0, 0
  self.stuckX, self.stuckY = 0, 0
  self.stuckTarget = nil

  self.drawing = false
  self.drawT = 0
  self.aimX, self.aimY = 1, 0
  self.pendingAmount = self.minSkip

  self.targetList = trimSplit(self.targets)
  self.standList  = trimSplit(self.standables)
  self.climbList  = trimSplit(self.climbables)
  self.solidList  = trimSplit(self.solids)
  self.stopList   = trimSplit(self.arrowStops)
  self.mirrorList = trimSplit(self.mirrors)
  self.bounces    = 0
  -- 乗っている足場(名前と前フレーム位置)。床が動いた分だけプレイヤーを一緒に運ぶ
  self.rideName  = nil
  self.ridePrevX = 0
  self.ridePrevY = 0

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
  end

  updateClimb(self, dt)  -- 登り中なら vx/vy をここで上書き
  if not self.climbing then
    self.vy = self.vy - self.gravity * dt
  end

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

local function fireArrow(self)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  local amount = lerp(self.minSkip, self.maxSkip, clamp(self.drawT / self.maxDrawTime, 0, 1))
  local ax, ay = self.aimX or self.facing, self.aimY or 0
  local p = self.transform.position
  local sx, sy, sz = p.x + ax * 0.7, p.y + 0.2 + ay * 0.3, p.z
  arrowE.transform.position = Vec3.new(sx, sy, sz)
  arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(ay, ax)))
  FX.spark(sx, sy, sz, 10, 0.3, 0.75, 1.0)

  self.hasArrow = false
  self.arrowFlying = true
  self.arrowVX, self.arrowVY = ax * self.arrowSpeed, ay * self.arrowSpeed
  self.shotFromX, self.shotFromY = p.x, p.y
  self.pendingAmount = amount
  self.bounces = 0
  self.drawT = 0
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
  local drawHeld = keyDown("E") or padDown("X")
  local canDraw = self.hasArrow and not self.arrowFlying and not self.arrowStuck

  if drawHeld and canDraw then
    if not self.drawing then
      self.drawing = true
      self.drawT = 0
      self.aimAngle = math.deg(math.atan(self.aimY or 0, self.aimX or self.facing))
    end
    self.drawT = math.min(self.drawT + dt, self.maxDrawTime)

    -- 目標方向へ aimTurnSpeed(度/秒)で少しずつ回す(WASDでも滑らかに旋回する照準)
    local tx, ty = aimTargetDir(self)
    local targetAngle = math.deg(math.atan(ty, tx))
    local delta = angleDelta(self.aimAngle, targetAngle)
    local maxStep = self.aimTurnSpeed * dt
    self.aimAngle = self.aimAngle + clamp(delta, -maxStep, maxStep)
    local rad = math.rad(self.aimAngle)
    local ax, ay = math.cos(rad), math.sin(rad)
    self.aimX, self.aimY = ax, ay

    local p = self.transform.position
    local frac = self.drawT / self.maxDrawTime
    local len = 1.1 + 2.3 * frac
    FX.beam(p.x, p.y + 0.2, p.z, p.x + ax * len, p.y + 0.2 + ay * len, p.z,
            0.4 + 0.4 * frac, 0.75 + 0.2 * frac, 1.0, 0.1, "energy", 3 + frac * 3)
  elseif self.drawing then
    self.drawing = false
    fireArrow(self)
  end
end

local function stickArrow(self, arrowE, hitTargetName)
  local ap = arrowE.transform.position
  self.arrowFlying = false
  self.arrowStuck = true
  self.stuckX, self.stuckY = ap.x, ap.y
  self.stuckTarget = hitTargetName
  if hitTargetName then
    events:emit("time_skip", { target = hitTargetName, amount = self.pendingAmount })
    FX.shockwave(ap.x, ap.y, ap.z, 12, 7, 0.3, 0.75, 1.0)
    fx:pulse(0.18)
    padVibrate(0.5, 0.3, 0.12)
  end
end

local function updateArrow(self, dt)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  if self.arrowFlying then
    local ap = arrowE.transform.position
    local nx, ny = ap.x + self.arrowVX * dt, ap.y + self.arrowVY * dt
    arrowE.transform.position = Vec3.new(nx, ny, ap.z)
    FX.trail(nx, ny, ap.z, 0.3, 0.75, 1.0)

    if tryReflect(self, arrowE, nx, ny) then return end

    local hitName = nil
    for _, name in ipairs(self.targetList) do
      local t = scene:findEntity(name)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        if overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf, tp.x, tp.y, ts.x * 0.5, ts.y * 0.5) then
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
      -- 奈落へ落ちた矢は回収不能(Rでリトライ)。画面外に留める
      self.arrowFlying = false
      self.arrowStuck = true
      self.stuckX, self.stuckY = nx, ny
      self.stuckTarget = nil
    elseif travelled > self.arrowRange * self.arrowRange then
      stickArrow(self, arrowE, nil)
    end
    return
  end

  if self.arrowStuck then
    local p = self.transform.position
    local recovered = false
    if self.stuckTarget then
      -- 刺さった的自身に触れる(的が動いていれば矢もそれに追従して表示する)
      local t = scene:findEntity(self.stuckTarget)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        arrowE.transform.position = Vec3.new(tp.x, tp.y, tp.z - 0.05)
        if overlapAABB(p.x, p.y, self.halfW, self.halfHeight, tp.x, tp.y, ts.x * 0.5, ts.y * 0.5) then
          recovered = true
        end
      else
        recovered = true  -- 的が消滅済みなら回収不能を回避し矢を返す
      end
    else
      if overlapAABB(p.x, p.y, self.halfW, self.halfHeight, self.stuckX, self.stuckY, self.arrowHalf, self.arrowHalf) then
        recovered = true
      end
    end
    if recovered then
      self.arrowStuck = false
      self.hasArrow = true
      self.stuckTarget = nil
      arrowE.transform.position = Vec3.new(0, -100, 0)
    end
  end
end

function OnUpdate(self, dt)
  for name, t in pairs(self.ghostSolids) do
    self.ghostSolids[name] = t - dt
  end
  carryByRide(self)
  unstick(self)
  updateMovement(self, dt)
  updateDraw(self, dt)
  updateArrow(self, dt)

  if keyPressed("ESC") or padPressed("START") then goToScene("scenes/title.json", 0.5) end
end
