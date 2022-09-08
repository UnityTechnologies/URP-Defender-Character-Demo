using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
 
public class BatchSetLodGroupWindow : EditorWindow{
 
    bool includeSubdirectories = true;
    LODFadeMode fadeMode = LODFadeMode.None;
 
    float cullRatio = 0.01f;
 
    public float[] lodWeights = new float[] { 0.6f, 0.3f, 0.1f };
 
    string path = string.Empty;
 
    [MenuItem("Tools/BatchSetLodGroups")]
    public static void ShowWindow() {
        //Show existing window instance. If one doesn't exist, make one.
        EditorWindow.GetWindow(typeof(BatchSetLodGroupWindow));
    }
 
    void OnGUI() {
 
        GUILayout.Label("LODGroup Settings", EditorStyles.boldLabel);
 
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.PrefixLabel("Select Directory");
        if (GUILayout.Button("Browse")) {
            path = EditorUtility.OpenFolderPanel("Select Directory", "", "");
        }
        EditorGUILayout.EndHorizontal();
 
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.PrefixLabel("Current Path");
        EditorGUILayout.LabelField(path);
        EditorGUILayout.EndHorizontal();
 
        includeSubdirectories = EditorGUILayout.Toggle("Include Subdirectories", includeSubdirectories);
 
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.PrefixLabel("Fade Mode");
        fadeMode = (LODFadeMode)EditorGUILayout.EnumPopup((Enum)fadeMode);
        EditorGUILayout.EndHorizontal();
 
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.PrefixLabel("Cull Ratio (0.01 = 1%)");
        cullRatio = EditorGUILayout.FloatField(cullRatio);
        EditorGUILayout.EndHorizontal();
 
        EditorGUILayout.LabelField("LOD Level Weights (will be normalized to 1)");
 
        ScriptableObject target = this;
        SerializedObject so = new SerializedObject(target);
        SerializedProperty prop = so.FindProperty(nameof(lodWeights));
        EditorGUILayout.PropertyField(prop, true); // True means show children
        so.ApplyModifiedProperties(); // Remember to apply modified properties
 
        
        if (GUILayout.Button("Apply")) {
            if (!string.IsNullOrWhiteSpace(path)) {
 
                PerformActionOnPrefab(path, this.includeSubdirectories, GetSetLoadGroup(fadeMode,cullRatio, this.lodWeights));
            }
        }
        
        EditorGUILayout.Space();
        GUILayout.Label("FadeMode Quike Setting", EditorStyles.boldLabel);
        
        if (GUILayout.Button("Switch FadeMode")) 
        {
            ReplaceFadeMode();
        }
 
        Func<GameObject, bool> GetSetLoadGroup(LODFadeMode fadeMode,float cullRatio, float[] lodWeights) {
            return x => SetLodGroupInner(x, fadeMode,cullRatio, lodWeights);
        }
 
        bool SetLodGroupInner(GameObject prefab, LODFadeMode fadeMode,float cullRatio, float[] lodWeights) {
 
            if (lodWeights == null || lodWeights.Length == 0) return false;
            LODGroup[] lodGroups = prefab.GetComponentsInChildren<LODGroup>(true);
 
            if (lodGroups == null || lodGroups.Length <= 0) {
                return false;
            }
 
            for (int i = 0; i < lodGroups.Length; i++) {
                LODGroup lodGroup = lodGroups[i];
 
                lodGroup.fadeMode = fadeMode;
                LOD[] lods = lodGroup.GetLODs();
 
                float weightSum = 0;
                for (int k = 0; k < lods.Length; k++) {
 
                    if (k >= lodWeights.Length) {
                        weightSum += lodWeights[lodWeights.Length - 1];
                    } else {
                        weightSum += lodWeights[k];
                    }
                }
 
 
                float maxLength = 1 - cullRatio;
                float curLodPos = 1;
                for (int j = 0; j < lods.Length; j++) {
 
                    float weight = j < lodWeights.Length ? lodWeights[j] : lodWeights[lodWeights.Length - 1];
 
                    float lengthRatio = weightSum != 0 ? weight / weightSum : 1;
 
                    float lodLength = maxLength * lengthRatio;
                    curLodPos = curLodPos - lodLength;
 
                    lods[j].screenRelativeTransitionHeight = curLodPos;
                }
 
 
                lodGroup.SetLODs(lods);
            }
 
            return true;
        }
    }
 
   
    //action: input prefab output should save to prefab
    void  PerformActionOnPrefab(string path, bool includeSubdirectories,Func<GameObject,bool> action) {
        string[] files = Directory.GetFiles(path,"*.prefab", includeSubdirectories ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly);
 
        foreach (var file in files) {
            GameObject prefabGO = PrefabUtility.LoadPrefabContents(file);
 
            if (prefabGO != null) {
                action(prefabGO);
 
                PrefabUtility.SaveAsPrefabAsset(prefabGO, file);
                PrefabUtility.UnloadPrefabContents(prefabGO);
            }
        }
 
    }
    
    public Material material_to_apply;
    void ReplaceFadeMode ()
    {
        GameObject [] gos = Selection.gameObjects;
        foreach( GameObject go in gos )
        {
            LODGroup[] lodGroups = go.GetComponentsInChildren<LODGroup>(true);
            if (lodGroups != null)
            {
                for (int i = 0; i < lodGroups.Length; i++)
                {
                    LODGroup lodGroup = lodGroups[i];
                    lodGroup.fadeMode = fadeMode;
                    Debug.Log(lodGroup.gameObject.name + "has been set to " + fadeMode.ToString());
                }
            }

        }
 
    }
 
}