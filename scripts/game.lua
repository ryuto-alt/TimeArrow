-- game.lua -- 全シーン共通のグローバルスクリプト(シーンロードごとに再読込される)。
-- 開発者コマンド置き場。
--   F2: トレーラー撮影用の全BGMミュート(トグル)。SEはそのまま。
--       セーブ値 dev_bgm_mute で持つのでシーン遷移・再起動をまたいで維持される。
--       各シーンのOnStartが音量を復元してくるので、ミュート中は毎フレーム0を強制する。

local VK_F2 = KEY_F2 or 0x71

function OnUpdate(dt)
  if input:isKeyPressed(VK_F2) then
    local muted = loadNum("dev_bgm_mute", 0) > 0.5
    if muted then
      saveNum("dev_bgm_mute", 0)
      audio:setBGMVolume(loadNum("opt_bgm", 1.0))
      log("[dev] BGM mute OFF")
    else
      saveNum("dev_bgm_mute", 1)
      log("[dev] BGM mute ON (trailer mode)")
    end
  end
  if loadNum("dev_bgm_mute", 0) > 0.5 then
    audio:setBGMVolume(0)   -- ponytail: 毎フレーム強制。シーン側の音量復元より確実に勝つ
  end
end
