/*******************************************************************************
* Direct PS4-to-motor firmware for TurtleBot3 Burger on OpenCR.
*
* Host protocol over the USB CDC serial port:
*   V <enable> <linear_mps> <angular_radps>\n
*   STOP\n
*   PING\n
*
* Safety:
* - If no valid velocity packet arrives within COMMAND_TIMEOUT_MS, the motors
*   are commanded to zero velocity.
* - The host should hold a deadman button and keep sending packets at 20+ Hz.
*******************************************************************************/

#include <Arduino.h>
#include <DynamixelSDK.h>

// Burger kinematics copied from the upstream turtlebot3_burger example so this
// sketch can be built from the repo without depending on example-local headers.
#define WHEEL_RADIUS 0.033f
#define WHEEL_SEPARATION 0.160f
#define TURNING_RADIUS 0.080f
#define MAX_LINEAR_VELOCITY (WHEEL_RADIUS * 2.0f * 3.14159265359f * 61.0f / 60.0f)
#define MAX_ANGULAR_VELOCITY (MAX_LINEAR_VELOCITY / TURNING_RADIUS)
#define MIN_LINEAR_VELOCITY (-MAX_LINEAR_VELOCITY)
#define MIN_ANGULAR_VELOCITY (-MAX_ANGULAR_VELOCITY)
#define VELOCITY_CONSTANT_VALUE 41.69988758f

#define DXL_LEFT_ID 1
#define DXL_RIGHT_ID 2
#define DXL_BAUDRATE 1000000
#define DXL_PROTOCOL_VERSION 2.0f
#define DXL_DEVICE_NAME ""
#define DXL_ADDR_TORQUE_ENABLE 64
#define DXL_ADDR_GOAL_VELOCITY 104
#define DXL_LEN_TORQUE_ENABLE 1
#define DXL_LEN_GOAL_VELOCITY 4
#define DXL_TORQUE_ENABLE 1
#define DXL_TORQUE_DISABLE 0
#define DXL_BURGER_LIMIT_MAX_VELOCITY 265

#define HOST_SERIAL Serial
#define HOST_BAUDRATE 115200
#define CONTROL_MOTOR_SPEED_FREQUENCY 30
#define COMMAND_TIMEOUT_MS 250

#define LINEAR 0
#define ANGULAR 1

float goal_velocity[2] = {0.0f, 0.0f};
float zero_velocity[2] = {0.0f, 0.0f};

uint32_t last_control_ms = 0;
uint32_t last_command_ms = 0;
bool command_enabled = false;

char line_buffer[80];
size_t line_length = 0;

dynamixel::PortHandler *port_handler = nullptr;
dynamixel::PacketHandler *packet_handler = nullptr;
dynamixel::GroupSyncWrite *group_sync_write_velocity = nullptr;

void writeStatus(const __FlashStringHelper *message)
{
  HOST_SERIAL.println(message);
}

void writeStatus(const char *message)
{
  HOST_SERIAL.println(message);
}

void stopRobot()
{
  goal_velocity[LINEAR] = 0.0f;
  goal_velocity[ANGULAR] = 0.0f;
}

bool setMotorTorque(uint8_t onoff)
{
  uint8_t dxl_error = 0;
  int dxl_comm_result = COMM_TX_FAIL;

  dxl_comm_result = packet_handler->write1ByteTxRx(
    port_handler, DXL_LEFT_ID, DXL_ADDR_TORQUE_ENABLE, onoff, &dxl_error);
  if (dxl_comm_result != COMM_SUCCESS || dxl_error != 0) {
    return false;
  }

  dxl_comm_result = packet_handler->write1ByteTxRx(
    port_handler, DXL_RIGHT_ID, DXL_ADDR_TORQUE_ENABLE, onoff, &dxl_error);
  if (dxl_comm_result != COMM_SUCCESS || dxl_error != 0) {
    return false;
  }

  return true;
}

bool initMotorDriver()
{
  port_handler = dynamixel::PortHandler::getPortHandler(DXL_DEVICE_NAME);
  packet_handler = dynamixel::PacketHandler::getPacketHandler(DXL_PROTOCOL_VERSION);

  if (port_handler == nullptr || packet_handler == nullptr) {
    return false;
  }

  if (!port_handler->openPort()) {
    return false;
  }

  if (!port_handler->setBaudRate(DXL_BAUDRATE)) {
    return false;
  }

  if (!setMotorTorque(DXL_TORQUE_ENABLE)) {
    return false;
  }

  group_sync_write_velocity = new dynamixel::GroupSyncWrite(
    port_handler, packet_handler, DXL_ADDR_GOAL_VELOCITY, DXL_LEN_GOAL_VELOCITY);

  return group_sync_write_velocity != nullptr;
}

bool writeWheelVelocityRaw(int32_t left_value, int32_t right_value)
{
  uint8_t left_data_byte[4] = {0, 0, 0, 0};
  uint8_t right_data_byte[4] = {0, 0, 0, 0};

  left_data_byte[0] = DXL_LOBYTE(DXL_LOWORD(left_value));
  left_data_byte[1] = DXL_HIBYTE(DXL_LOWORD(left_value));
  left_data_byte[2] = DXL_LOBYTE(DXL_HIWORD(left_value));
  left_data_byte[3] = DXL_HIBYTE(DXL_HIWORD(left_value));

  right_data_byte[0] = DXL_LOBYTE(DXL_LOWORD(right_value));
  right_data_byte[1] = DXL_HIBYTE(DXL_LOWORD(right_value));
  right_data_byte[2] = DXL_LOBYTE(DXL_HIWORD(right_value));
  right_data_byte[3] = DXL_HIBYTE(DXL_HIWORD(right_value));

  if (!group_sync_write_velocity->addParam(DXL_LEFT_ID, left_data_byte)) {
    group_sync_write_velocity->clearParam();
    return false;
  }

  if (!group_sync_write_velocity->addParam(DXL_RIGHT_ID, right_data_byte)) {
    group_sync_write_velocity->clearParam();
    return false;
  }

  const int dxl_comm_result = group_sync_write_velocity->txPacket();
  group_sync_write_velocity->clearParam();
  return dxl_comm_result == COMM_SUCCESS;
}

bool controlMotorVelocity(float linear, float angular)
{
  float left_velocity_cmd = linear - (angular * WHEEL_SEPARATION / 2.0f);
  float right_velocity_cmd = linear + (angular * WHEEL_SEPARATION / 2.0f);

  left_velocity_cmd = constrain(
    left_velocity_cmd * VELOCITY_CONSTANT_VALUE / WHEEL_RADIUS,
    -DXL_BURGER_LIMIT_MAX_VELOCITY,
    DXL_BURGER_LIMIT_MAX_VELOCITY);
  right_velocity_cmd = constrain(
    right_velocity_cmd * VELOCITY_CONSTANT_VALUE / WHEEL_RADIUS,
    -DXL_BURGER_LIMIT_MAX_VELOCITY,
    DXL_BURGER_LIMIT_MAX_VELOCITY);

  return writeWheelVelocityRaw(
    static_cast<int32_t>(left_velocity_cmd),
    static_cast<int32_t>(right_velocity_cmd));
}

bool handleVelocityCommand(const char *line)
{
  int enabled = 0;
  float linear = 0.0f;
  float angular = 0.0f;

  if (sscanf(line, "V %d %f %f", &enabled, &linear, &angular) != 3) {
    return false;
  }

  linear = constrain(linear, MIN_LINEAR_VELOCITY, MAX_LINEAR_VELOCITY);
  angular = constrain(angular, MIN_ANGULAR_VELOCITY, MAX_ANGULAR_VELOCITY);

  command_enabled = (enabled != 0);
  goal_velocity[LINEAR] = command_enabled ? linear : 0.0f;
  goal_velocity[ANGULAR] = command_enabled ? angular : 0.0f;
  last_command_ms = millis();

  return true;
}

void processLine(char *line)
{
  if (strcmp(line, "STOP") == 0 || strcmp(line, "ESTOP") == 0) {
    command_enabled = false;
    stopRobot();
    last_command_ms = millis();
    writeStatus("OK STOP");
    return;
  }

  if (strcmp(line, "PING") == 0) {
    writeStatus("OK PONG");
    return;
  }

  if (handleVelocityCommand(line)) {
    writeStatus("OK V");
    return;
  }

  writeStatus("ERR");
}

void readHostSerial()
{
  while (HOST_SERIAL.available() > 0) {
    const char ch = static_cast<char>(HOST_SERIAL.read());

    if (ch == '\r') {
      continue;
    }

    if (ch == '\n') {
      line_buffer[line_length] = '\0';
      if (line_length > 0) {
        processLine(line_buffer);
      }
      line_length = 0;
      continue;
    }

    if (line_length + 1 >= sizeof(line_buffer)) {
      line_length = 0;
      writeStatus("ERR OVERFLOW");
      continue;
    }

    line_buffer[line_length++] = ch;
  }
}

void setup()
{
  HOST_SERIAL.begin(HOST_BAUDRATE);
  last_command_ms = millis();

  if (!initMotorDriver()) {
    writeStatus("ERR MOTOR_INIT");
    while (true) {
      delay(100);
    }
  }

  stopRobot();
  controlMotorVelocity(0.0f, 0.0f);
  writeStatus("READY");
}

void loop()
{
  const uint32_t now = millis();

  readHostSerial();

  if ((now - last_command_ms) > COMMAND_TIMEOUT_MS) {
    command_enabled = false;
    stopRobot();
  }

  if ((now - last_control_ms) >= (1000 / CONTROL_MOTOR_SPEED_FREQUENCY)) {
    if (command_enabled) {
      controlMotorVelocity(goal_velocity[LINEAR], goal_velocity[ANGULAR]);
    } else {
      controlMotorVelocity(0.0f, 0.0f);
    }
    last_control_ms = now;
  }
}
