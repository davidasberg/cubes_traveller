using UnityEngine;

public class PlayerController : MonoBehaviour
{


    [SerializeField]
    private float playerSpeed = 2.0f;

    [SerializeField]
    private float jumpForce = 5.0f;

    [SerializeField]
    Transform cubeTransform; // Assign this in the inspector

    [SerializeField]
    LayerMask cubeLayerMask;

    [SerializeField]
    Animator animator;

    private Rigidbody rb;
    private float horizontalInput;
    private float verticalInput;

    private bool jumpInput;
    private bool isGrounded;

    private float jumpTimer = 0.0f;

    private float jumpDelay = 0.2f;


    // Position relative to the rotation of the cube
    public Vector3 cubeRelativePosition;
    public Vector3 cubeRelativeRotation;

    // Model direction 
    private Vector3 moveDir;

    private void Start()
    {
        rb = gameObject.GetComponent<Rigidbody>();
        cubeRelativePosition = cubeTransform.InverseTransformPoint(transform.position);
    }


    void Update()
    {
        // get input from player
        horizontalInput = Input.GetAxisRaw("Horizontal");
        verticalInput = Input.GetAxisRaw("Vertical");

        // catch jump event
        jumpInput = Input.GetButton("Jump");


    }

    void FixedUpdate()
    {

        // current position relative to the cube
        Vector3 currentPosition = cubeTransform.TransformPoint(cubeRelativePosition);

        // raycast from the player to the cube origin
        // the face it hits is the face that is facing the player
        RaycastHit hit;
        Vector3 rayDir = cubeTransform.position - currentPosition;
        Vector3 currentNormal = transform.up;
        if (Physics.Raycast(currentPosition + transform.up * 0.1f, rayDir, out hit, Mathf.Infinity, cubeLayerMask))
        {
            currentNormal = hit.normal;
        }
        Quaternion currentRotation = Quaternion.LookRotation(cubeTransform.TransformDirection(cubeRelativeRotation), currentNormal);

        // if the face is facing the camera, vertical input is up/down
        // if they are orthogonal, vertical input is forward/backward
        // if the face is facing away from the camera, vertical input is reversed

        // dot product of the normal and the camera forward
        // this is used to determine if the current face is facing the camera
        float faceCameraAlignment = Vector3.Dot(-currentNormal, Camera.main.transform.forward);

        // create a inverse 'v' shape for the forward/backward scale, from 0 to 1
        float forwardBackwardScale = Mathf.Abs(faceCameraAlignment) * -1.0f + 1.0f;

        // create a vector from the input, saturate it so that diagonal movement isn't faster
        Vector3 input = new Vector3(horizontalInput, verticalInput * faceCameraAlignment, verticalInput * forwardBackwardScale);
        float inputSpeed = Mathf.Min(input.magnitude, 1.0f);

        // transform it from camera space to world space
        // this makes movement relative to the camera, which is more intuitive
        moveDir = Camera.main.transform.TransformDirection(input).normalized;

        // project the move vector onto the plane of the face
        moveDir = Vector3.ProjectOnPlane(moveDir, currentNormal).normalized;

        Vector3 newPos = currentPosition + inputSpeed * playerSpeed * Time.fixedDeltaTime * moveDir;
        rb.MovePosition(newPos);

        // if the player isn't moving, don't rotate them
        // and set the walking animation to false
        Quaternion targetRotation;
        if (moveDir.magnitude < 0.01f)
        {
            targetRotation = Quaternion.FromToRotation(transform.up, currentNormal) * currentRotation;
            animator.SetBool("IsWalking", false);
        }
        else
        {
            targetRotation = Quaternion.LookRotation(moveDir, currentNormal);
            animator.SetBool("IsWalking", true);
        }

        // rotate the player to align with the face normal
        // TODO: rework this after demo
        rb.MoveRotation(Quaternion.Slerp(currentRotation, targetRotation, 0.4f));

        // apply gravity
        rb.AddForce(Physics.gravity.magnitude * -currentNormal);

        // TODO: rework this after demo
        // check if the player is grounded
        jumpTimer -= Time.fixedDeltaTime;
        isGrounded = false;
        Debug.DrawRay(currentPosition, -currentNormal * 0.05f, Color.magenta);

        if (Physics.Raycast(currentPosition, -currentNormal, out hit))
        {
            if (hit.distance < 0.05f)
            {
                isGrounded = true;
            }
        }

        // jump
        bool canJump = jumpTimer <= 0.0f;
        if (jumpInput && isGrounded && canJump)
        {
            rb.AddForce(currentNormal * jumpForce, ForceMode.VelocityChange);
            jumpTimer = jumpDelay;
            animator.SetTrigger("Jump");
        }

    }
}