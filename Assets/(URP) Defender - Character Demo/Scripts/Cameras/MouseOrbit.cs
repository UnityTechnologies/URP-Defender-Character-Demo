using UnityEngine;

[AddComponentMenu("Camera-Control/Mouse Orbit")]
public class MouseOrbit : MonoBehaviour
{   
    public Transform target;
    public Vector3 targetOffset = Vector3.zero;

    public float distance   = 100.0f;
    public float xSpeed     = 120.0f;
    public float ySpeed     = 120.0f;
    public float zoomSpeed  = 1f;
    public float yMaxLimit  = 80f;
    public float yMinLimit  = -80f;

    private float x;
    private float y;
    private Rigidbody m_RigidBody;
    private bool mobilePlatform = false;
    private bool rotateOn = true;
    private Vector3 position;
    private Quaternion rotation;
    private float dolly;
    private float zoomInOut;


    private void Start()
    {
        mobilePlatform = (Application.platform == RuntimePlatform.Android) || (Application.platform == RuntimePlatform.IPhonePlayer);

        if (target == null)
        {
            target = new GameObject().transform;
            target.position = Vector3.zero;
        }

        var angles = transform.eulerAngles;
        x = angles.y;
        y = angles.x;

        // If camera has Rigidbody
        m_RigidBody = GetComponent<Rigidbody>();
        // Make the rigid body not change rotation
        if (m_RigidBody)
            m_RigidBody.freezeRotation = true;
        OrbitAndDolly();
    }

    private void Update()
    {
        

        // PC platform -------------------------------
        if (!mobilePlatform)
        {    
            // Left mouse button to Orbit the camera and Mouse Scrollwheel to Dally and Orbit the camera
            if ((Input.GetAxis("Mouse ScrollWheel") < 0) || Input.GetMouseButton(0))
            {
                distance += zoomSpeed * Time.deltaTime;
                OrbitAndDolly();
            }

            if ((Input.GetAxis("Mouse ScrollWheel") > 0) || Input.GetMouseButton(0))
            {
                distance -= zoomSpeed * Time.deltaTime;
                OrbitAndDolly();
            }
        }

        // Mobile platform ----------------------------
        else
        {
            if (Input.touchCount == 1 && rotateOn)
            {
                Touch touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Moved)
                {
                    x += (touch.deltaPosition.x) * xSpeed * 1.5e-3f;
                    y -= (touch.deltaPosition.y) * ySpeed * 1.5e-3f;

                    y = ClampAngle(y, yMinLimit, yMaxLimit);

                    rotation = Quaternion.Euler(y, x, 0);
                    position = rotation * new Vector3(0.0f, 0.0f, -distance) + target.position + targetOffset;

                    transform.rotation = rotation;
                    transform.position = position;
                }
            }
        }
    }

    private void OrbitAndDolly()
    {
        if (target)
        {
            x += Input.GetAxis("Mouse X") * xSpeed * 0.02f;
            y -= Input.GetAxis("Mouse Y") * ySpeed * 0.02f;

            y = ClampAngle(y, yMinLimit, yMaxLimit);

            var rotation = Quaternion.Euler(y, x, 0);
            var position = rotation * new Vector3(0.0f, -target.position.y, -distance) + target.position + targetOffset;
            
            transform.rotation = rotation;
            transform.position = position;
        }
    }

    private static float ClampAngle(float angle, float min, float max)
    {
        if (angle < -360)
            angle += 360;
        if (angle > 360)
            angle -= 360;
        return Mathf.Clamp(angle, min, max);
    }

    // Reset the Camera position and rotation
    public void ResetPosition()
    {
        distance = 1.0f;
        var rotation = Quaternion.Euler(0, 180f, 0);
        var position = new Vector3(0.0f, 0.0f, 1f);

        transform.rotation = rotation;
        transform.position = position;
    }

    public void SetRotateMode(bool newMode)
    {
        rotateOn = newMode;
    }
}