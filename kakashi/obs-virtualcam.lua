-- Script di OBS usato da Kakashi: accende la camera virtuale dopo l'avvio, aspettando che l'estensione sia pronta.
obs = obslua
local tries = 0

function try_start()
  tries = tries + 1
  if obs.obs_frontend_virtualcam_active() then
    obs.timer_remove(try_start)
    return
  end
  obs.obs_frontend_start_virtualcam()
  if tries >= 6 then obs.timer_remove(try_start) end
end

function script_description()
  return "Kakashi: accende la camera virtuale all'avvio."
end

function script_load(settings)
  obs.timer_add(try_start, 5000)
end
