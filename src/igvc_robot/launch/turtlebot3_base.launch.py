import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.actions import SetEnvironmentVariable
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.actions import PushRosNamespace


def generate_launch_description():
    igvc_share = get_package_share_directory("igvc_robot")
    tb3_bringup_share = get_package_share_directory("turtlebot3_bringup")

    namespace = LaunchConfiguration("namespace")
    use_sim_time = LaunchConfiguration("use_sim_time")
    opencr_port = LaunchConfiguration("opencr_port")
    tb3_param_dir = LaunchConfiguration("tb3_param_dir")

    state_publisher_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(tb3_bringup_share, "launch", "turtlebot3_state_publisher.launch.py")
        ),
        launch_arguments={
            "use_sim_time": use_sim_time,
            "namespace": namespace,
        }.items(),
    )

    turtlebot3_node = Node(
        package="turtlebot3_node",
        executable="turtlebot3_ros",
        parameters=[
            tb3_param_dir,
            {"namespace": namespace},
        ],
        arguments=["-i", opencr_port],
        output="screen",
    )

    return LaunchDescription(
        [
            SetEnvironmentVariable("TURTLEBOT3_MODEL", "burger"),
            DeclareLaunchArgument(
                "namespace",
                default_value="",
                description="Namespace for the TurtleBot3 base nodes",
            ),
            DeclareLaunchArgument(
                "use_sim_time",
                default_value="false",
                description="Use simulation clock if true",
            ),
            DeclareLaunchArgument(
                "opencr_port",
                default_value="/dev/ttyACM0",
                description="Connected USB port for the OpenCR board (use ttyACM1 if that is the active node)",
            ),
            DeclareLaunchArgument(
                "tb3_param_dir",
                default_value=PathJoinSubstitution(
                    [igvc_share, "config", "turtlebot3_burger.yaml"]
                ),
                description="Full path to TurtleBot3 Burger parameter file",
            ),
            PushRosNamespace(namespace),
            state_publisher_launch,
            turtlebot3_node,
        ]
    )
