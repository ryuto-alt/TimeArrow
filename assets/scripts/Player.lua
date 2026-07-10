-- Player.lua -- 「時を先送りさせる矢」プレイヤー本体。
-- 横視点プラットフォーマー(独自の重力/移動を手書き。物理エンジンJoltは使わない。ShardRunnerと同じ流儀)。
-- 弓矢: 1本のみ所持。E=先送り矢(前方スキップ)を放つ / Q=巻き戻し矢(canRewind時のみ)。
-- 刺さったオブジェクトに触れる(=矢が刺さった"その場"に触れる)ことで矢を回収できる。
properties = {
  { name = "speed",        type = "float",  default = 6.0,  min = 1,  max = 15, label = "移動速度" },
  { name = "jumpSpeed",     type = "float",  default = 9.5,  min = 1,  max = 20, label = "ジャンプ初速" },
  { name = "gravity",       type = "float",  default = 22.0, min = 1,  max = 60, label = "重力加速度" },
  { name = "groundY",       type = "float",  default = 0.0,                     label = "地面のY" },
  { name = "halfHeight",    type = "float",  default = 0.8,  min = 0.1, max = 3, label = "スプライト半分の高さ(接地オフセット)" },
  { name = "arrowSpeed",    type = "float",  default = 14.0, min = 1,  max = 40, label = "矢の速度(等速直線運動)" },
  { name = "arrowRange",    type = "float",  default = 16.0, min = 1,  max = 60, label = "矢の最大飛距離" },
  { name = "hitRadius",     type = "float",  default = 1.0,  min = 0.1, max = 5, label = "矢の命中判定半径" },
  { name = "recoverRadius", type = "float",  default = 1.0,  min = 0.1, max = 5, label = "矢の回収判定半径" },
  { name = "skipAmount",    type = "float",  default = 1.0,  min = 0,  max = 10, label = "先送り/巻き戻し量" },
  { name = "canRewind",     type = "bool",   default = false,                   label = "巻き戻し矢を使えるか" },
  { name = "targets",       type = "string", default = "",                      label = "先送り対象(カンマ区切り)" },
  { name = "camOffsetX",    type = "float",  default = 0.0,                     label = "カメラXオフセット" },
  { name = "camOffsetY",    type = "float",  default = 2.5,                     label = "カメラYオフセット" },
  { name = "camOffsetZ",    type = "float",  default = -13.0,                   label = "カメラZオフセット" },
}

local function trimSplit(csv)
  local out = {}
  for w in string.gmatch(csv or "", "[^,]+") do
    local name = w:match("^%s*(.-)%s*$")
    if name ~= "" then out[#out + 1] = name end
  end
  return out
end

function OnStart(self)
  local p = self.transform.position
  self.startX, self.startY, self.startZ = p.x, p.y, p.z
  self.vx, self.vy = 0, 0
  self.facing = 1
  self.grounded = false

  self.hasArrow = true
  self.arrowFlying = false
  self.arrowStuck = false
  self.arrowVX = 0
  self.arrowDir = 1
  self.stuckX, self.stuckY = 0, 0

  self.targetList = trimSplit(self.targets)

  -- 開始位置が地面に埋まっていた場合の保険として、初回のみ接地高さへスナップする
  if p.y < self.groundY + self.halfHeight then
    self.transform.position = Vec3.new(p.x, self.groundY + self.halfHeight, p.z)
    self.startY = self.groundY + self.halfHeight
  end

  -- 矢オブジェクトは開始時は画面外(下方)に隠しておく
  local arrowE = scene:findEntity("Arrow")
  if arrowE and arrowE:isValid() then
    arrowE.transform.position = Vec3.new(0, -100, 0)
    scene:setColor(arrowE, 1.0, 0.35, 0.1)
  end

  events:on("player_died", function(data)
    self.respawnPending = true
  end)
end

local function respawn(self)
  self.transform.position = Vec3.new(self.startX, self.startY, self.startZ)
  self.vx, self.vy = 0, 0
  self.respawnPending = false
end

local function updateMovement(self, dt)
  local move = 0
  if keyDown("LEFT") or keyDown("A") then move = move - 1 end
  if keyDown("RIGHT") or keyDown("D") then move = move + 1 end
  if move ~= 0 then self.facing = move end

  self.vx = move * self.speed

  if self.grounded and (keyPressed("SPACE") or keyPressed("UP") or keyPressed("W")) then
    self.vy = self.jumpSpeed
    self.grounded = false
  end

  self.vy = self.vy - self.gravity * dt

  local p = self.transform.position
  local nx = p.x + self.vx * dt
  local ny = p.y + self.vy * dt

  -- 接地面はスプライト中心ではなく足元(中心 - 半分の高さ)基準にする
  local restY = self.groundY + self.halfHeight
  if ny <= restY then
    ny = restY
    self.vy = 0
    self.grounded = true
  else
    self.grounded = false
  end

  self.transform.position = Vec3.new(nx, ny, p.z)
  -- 左右反転はマイナススケールではなくY180度回転で行う(スケール反転だと
  -- ワールド行列の符号が反転し毎フレーム描画がちらつく問題があったため)
  self.transform.rotation = Vec3.new(0, self.facing < 0 and 180 or 0, 0)

  if ny < -8 then
    respawn(self)
  end
end

local function tryShoot(self)
  if not self.hasArrow or self.arrowFlying or self.arrowStuck then return end
  local dir = nil
  if keyPressed("E") then dir = 1 end
  if self.canRewind and keyPressed("Q") then dir = -1 end
  if not dir then return end

  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  local p = self.transform.position
  arrowE.transform.position = Vec3.new(p.x + self.facing * 0.7, p.y + 0.2, p.z)
  self.hasArrow = false
  self.arrowFlying = true
  self.arrowDir = dir
  self.arrowVX = self.facing * self.arrowSpeed
  self.shotFromX = p.x
end

local function stickArrow(self, arrowE, hitTargetName)
  local ap = arrowE.transform.position
  self.arrowFlying = false
  self.arrowStuck = true
  self.stuckX, self.stuckY = ap.x, ap.y

  if hitTargetName then
    events:emit("time_skip", { target = hitTargetName, dir = self.arrowDir, amount = self.skipAmount })
  end
end

local function updateArrow(self, dt)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  if self.arrowFlying then
    local ap = arrowE.transform.position
    local nx = ap.x + self.arrowVX * dt
    arrowE.transform.position = Vec3.new(nx, ap.y, ap.z)

    local hitName = nil
    for _, name in ipairs(self.targetList) do
      local t = scene:findEntity(name)
      if t and t:isValid() then
        local tp = t.transform.position
        local dx, dy = nx - tp.x, ap.y - tp.y
        if dx * dx + dy * dy < self.hitRadius * self.hitRadius then
          hitName = name
          break
        end
      end
    end

    if hitName then
      stickArrow(self, arrowE, hitName)
    elseif math.abs(nx - self.shotFromX) > self.arrowRange then
      stickArrow(self, arrowE, nil)
    end
    return
  end

  if self.arrowStuck then
    local p = self.transform.position
    local dx, dy = p.x - self.stuckX, p.y - self.stuckY
    if dx * dx + dy * dy < self.recoverRadius * self.recoverRadius then
      self.arrowStuck = false
      self.hasArrow = true
      arrowE.transform.position = Vec3.new(0, -100, 0)
    end
  end
end

local function updateCamera(self)
  local cam = scene:findEntity("GameCamera")
  if cam and cam:isValid() then
    local p = self.transform.position
    cam.transform.position = Vec3.new(p.x + self.camOffsetX, self.camOffsetY, self.camOffsetZ)
  end
end

function OnUpdate(self, dt)
  if self.respawnPending then respawn(self) end
  updateMovement(self, dt)
  tryShoot(self)
  updateArrow(self, dt)
  updateCamera(self)

  local arrowState = self.hasArrow and "READY" or (self.arrowFlying and "FLYING" or "STUCK (touch it to recover)")
  ui:text(20, 20, "Arrow: " .. arrowState, 22, 1, 1, 1, 1)
  if keyPressed("ESC") then goToScene("scenes/title.json", 0.5) end
end