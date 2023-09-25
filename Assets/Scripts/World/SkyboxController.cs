using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SkyboxController : MonoBehaviour
{
    public Light sun;
    public Light moon;

    [SerializeField, Range(0, 24)]
    private float timeOfDay = 0.0f;

    [SerializeField, Range(0.01f, 1.0f)]
    private float timeScale = 1.0f;

    public AnimationCurve sunCurve;
    public AnimationCurve moonCurve;

    private void Update()
    {
        timeOfDay += Time.deltaTime * timeScale;
        timeOfDay %= 24;

        // normalize timeOfDay to 0..1
        float n_time = timeOfDay / 24;

        sun.transform.localRotation = Quaternion.Euler(new Vector3(n_time * 360f - 90f, -30f, 0));
        moon.transform.localRotation = Quaternion.Euler(new Vector3(n_time * 360f + 90f, -30f, 0));

        sun.intensity = sunCurve.Evaluate(n_time);
        moon.intensity = moonCurve.Evaluate(n_time);
    }
}