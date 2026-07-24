-- TutPadDemo.lua -- stage0 の背景に浮かぶXBOXコントローラーの操作デモ。TutPad(本体)にアタッチ。
-- パーツ(TutPadStick/BtnA/BtnX/LB/RB)は全て「共通原点エクスポート」なので、
-- 全エンティティを同位置+同回転+同スケールに置くと組み上がる。アニメは各パーツの平行移動のみ
-- (回転合成の罠を避ける)。Tutorial.lua の events "tut_step" {kind=...} で現ステップの操作を再生する。
properties = {
  { name = "rotX", type = "float", default = 65.0, min = -180, max = 180, label = "見せる傾き(X)" },
  { name = "rotY", type = "float", default = 180.0,   min = -180, max = 180, label = "見せる向き(Y)" },
  { name = "bobAmp", type = "float", default = 0.06, min = 0, max = 0.5, label = "浮遊ボブの振幅" },
  { name = "rotZ", type = "float", default = 0.0, min = -180, max = 180, label = "ロール(ミラー出力と対で180)" },
  { name = "offX", type = "float", default = -4.5, min = -20, max = 20, label = "カメラ中心からのX(画面左上に置く)" },
  { name = "offY", type = "float", default = 1.8,  min = -20, max = 20, label = "カメラ中心からのY" },
}

local PART_NAMES = { "TutPadStick", "TutPadBtnA", "TutPadBtnX", "TutPadLB", "TutPadRB" }

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.scl = self.transform.scale.x
  self.t = 0
  self.mode = "walk"
  self.shown = false     -- 最初のステップ表示(tut_step)まで隠す=開幕バナーと出番をずらす

  self.parts = {}
  for _, n in ipairs(PART_NAMES) do
    local e = scene:findEntity(n)
    if e and e:isValid() then self.parts[n] = e end
  end

  -- 回転後のローカル軸(平行移動アニメ用)。エンジンのRollPitchYawに合わせ roll(Z)→pitch(X)→yaw(Y)
  local function computeAxes(self)
    local function rot(vx, vy, vz)
      local px, py, pz = math.rad(self.rotX), math.rad(self.rotY), math.rad(self.rotZ or 0)
      local x = vx * math.cos(pz) - vy * math.sin(pz)          -- roll(Z)
      local y = vx * math.sin(pz) + vy * math.cos(pz)
      local z = vz
      y, z = y * math.cos(px) - z * math.sin(px), y * math.sin(px) + z * math.cos(px)  -- pitch(X)
      local cy, sy = math.cos(py), math.sin(py)                -- yaw(Y)
      return { x * cy + z * sy, y, -x * sy + z * cy }
    end
    self.axUp    = rot(0, 1, 0)    -- 面の法線(ボタン押し込みはこの逆向き)
    self.axRight = rot(1, 0, 0)    -- スティック左右
    self.axTop   = rot(0, 0, -1)   -- 面の上方向(バンパー側)=スティック上下
  end
  computeAxes(self)

  events:on("tut_step", function(d)
    self.mode = d.kind or "walk"
    self.t = 0
    if not self.shown then
      self.shown = true
      self.showT = 0          -- 登場アニメ(ポップイン)開始
    else
      self.stepPulseT = 0     -- ステップ切替はドクンと脈打つ
    end
  end)
  events:on("stage_cleared", function() self.shown = false end)   -- クリア演出の邪魔をしない
  -- 向き/位置の実測チューニング用(evalから emit して調整)
  events:on("tutpad_rot", function(d)
    self.rotX = d.x or self.rotX
    self.rotY = d.y or self.rotY
    self.rotZ = d.z or self.rotZ
    self.offX = d.ox or self.offX
    self.offY = d.oy or self.offY
    computeAxes(self)
  end)
end

local function mul(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function add3(a, b, c)
  return { (a and a[1] or 0) + (b and b[1] or 0) + (c and c[1] or 0),
           (a and a[2] or 0) + (b and b[2] or 0) + (c and c[2] or 0),
           (a and a[3] or 0) + (b and b[3] or 0) + (c and c[3] or 0) }
end

function OnUpdate(self, dt)
  self.t = self.t + dt
  local t = self.t
  local s = self.scl

  -- パーツ別オフセット(OBJ単位×スケール)
  local off = {}
  local press = mul(self.axUp, -0.035 * s)     -- ボタン押し込み

  if self.mode == "walk" then
    off.TutPadStick = mul(self.axRight, math.sin(t * 3.2) * 0.07 * s)
  elseif self.mode == "jump" then
    if (t % 1.0) < 0.28 then off.TutPadBtnA = press end
  elseif self.mode == "look" then
    if (t % 1.8) < 1.1 then off.TutPadBtnX = press end
  elseif self.mode == "draw" then
    if (t % 2.2) < 1.5 then off.TutPadRB = press end
  elseif self.mode == "aim" then
    off.TutPadRB = press                          -- RBは押しっぱなし
    off.TutPadStick = mul(self.axTop, math.sin(t * 3.0) * 0.06 * s)
  elseif self.mode == "shoot" then
    -- ため(1.2s)→パッと放す、を繰り返す
    if (t % 2.0) < 1.2 then off.TutPadRB = press end
  elseif self.mode == "rw" then
    if (t % 2.2) < 1.5 then off.TutPadLB = press end
  end
  -- goal / それ以外: 操作なし(浮遊のみ)

  -- カメラ追従: どのステップでも画面左上に必ず見える(ステップと同期して出現)
  local ax, ay = self.bx, self.by
  local cam = scene:findEntity("GameCamera")
  if cam and cam:isValid() then
    local cp = cam.transform.position
    ax, ay = cp.x + self.offX, cp.y + self.offY
  end
  if not self.shown then ay = -100 end

  -- 登場アニメ: 0→1 に easeOutBack で膨らみ、火花付きでポップイン
  local sMul = 1.0
  if self.showT then
    self.showT = self.showT + dt
    local u = math.min(self.showT / 0.5, 1.0)
    local c1, c3 = 1.70158, 2.70158
    sMul = 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2       -- easeOutBack
    if self.showT < dt * 1.5 then
      FX.spark(ax, ay, self.bz, 16, 0.6, 0.8, 1.0)
      FX.shockwave(ax, ay, self.bz, 8, 5, 0.4, 0.7, 1.0)
    end
    if u >= 1.0 then self.showT = nil end
  end
  -- ステップ切替パルス
  if self.stepPulseT then
    self.stepPulseT = self.stepPulseT + dt
    local u = math.min(self.stepPulseT / 0.3, 1.0)
    sMul = sMul * (1 + 0.10 * math.sin(u * math.pi))
    if u >= 1.0 then self.stepPulseT = nil end
  end

  local bob = math.sin(t * 1.6) * self.bobAmp
  local rot = Vec3.new(self.rotX, self.rotY, (self.rotZ or 0) + math.sin(t * 1.1) * 3.0)  -- ゆらぎ
  local scl = self.scl * math.max(sMul, 0.001)

  self.transform.position = Vec3.new(ax, ay + bob, self.bz)
  self.transform.rotation = rot
  self.transform.scale = Vec3.new(scl, scl, scl)
  for n, e in pairs(self.parts) do
    if e:isValid() then
      local o = add3(off[n], nil, nil)
      e.transform.position = Vec3.new(ax + o[1] * sMul, ay + bob + o[2] * sMul, self.bz + o[3] * sMul)
      e.transform.rotation = rot
      e.transform.scale = Vec3.new(scl, scl, scl)
    end
  end
end
