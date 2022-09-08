using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SetFrameRate : MonoBehaviour
{
    void Awake()
    {
        // Actually this setting is only for mobile platform maximum performance test
#if (UNITY_IOS || UNITY_ANDROID)
        Application.targetFrameRate = 120;
# endif

    }

}
