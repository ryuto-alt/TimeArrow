-- BGProp.lua -- 背景装飾(BG_*モデル)のアイドル動作+時間消滅。
-- 歯車の回転・浮遊岩の上下はここで動かす(ギミックとは無関係の純装飾)。
-- T>0 なら「ステージ制限時間の全体を使って徐々に砕けて消える」進行度(0..1)を
-- BackdropLayer.hlsl へ毎フレーム送る(0秒で完全消滅)。
-- 弓の構え中(time_scaleイベント)は動きも消滅もスローになり、+10フラグで
-- シェーダーが青白い減彩に切り替わる(BackgroundCollapse.luaと同じ言語)。
properties = {
  { name = "spinZ",     type = "float", default = 0.0, min = -180, max = 180, label = "Z回転速度(度/秒, 歯車用)" },
  { name = "bobAmp",    type = "float", default = 0.0, min = 0,    max = 5,   label = "上下浮遊の振れ幅(浮遊岩用)" },
  { name = "bobPeriod", type = "float", default = 9.0, min = 1,    max = 60,  label = "浮遊の周期(秒)" },
  { name = "phase",     type = "float", default = 0.0, min = 0,    max = 60,  label = "位相オフセット(秒)" },
  { name = "T",         type = "float", default = 0.0, min = 0,    max = 300, label = "ステージ制限時間(0=時間消滅なし)" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  local r = self.transform.rotation
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.rx, self.ry = r.x, r.y
  self.spin = r.z
  self.clock = self.phase
  self.life = 0
  self.slowSent = -1
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
  self.clock = self.clock + dt
  self.life = self.life + dt

  if self.spinZ ~= 0 then
    self.spin = (self.spin + self.spinZ * dt) % 360
    self.transform.rotation = Vec3.new(self.rx, self.ry, self.spin)
  end
  if self.bobAmp > 0 then
    local ny = self.by + math.sin((self.clock / self.bobPeriod) * math.pi * 2) * self.bobAmp
    self.transform.position = Vec3.new(self.bx, ny, self.bz)
  end

  local slow = (self.ts or 1) < 1 and 10 or 0
  if self.T > 0 then
    -- 消滅進行度は毎フレーム送る(スローモーション中は進行も遅くなる)
    local frac = math.min(self.life / self.T, 1)
    local e = scene:findEntity(self.name)
    if e and e:isValid() then scene:setMeshEffect(e, frac + slow) end
    self.slowSent = -1
  elseif slow ~= self.slowSent then
    local e = scene:findEntity(self.name)
    if e and e:isValid() then
      scene:setMeshEffect(e, slow)
      self.slowSent = slow
    end
  end
end
