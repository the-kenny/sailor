defmodule Sailor.LocalDiscoveryTest do
  use ExUnit.Case
  require Sailor.LocalDiscovery, as: LD

  doctest Sailor.LocalDiscovery

  test "parse_annoucement matches net:" do
    {:ok, ip, port, _public_key} = LD.parse_announcement("net:fe80::aede:48ff:fe00:1122:8008~shs:mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=")
    assert 'fe80::aede:48ff:fe00:1122' = :inet.ntoa(ip)
    assert 8008 = port
  end

  test "parse_annoucements" do
    matches = LD.parse_announcements("net:fe80::aede:48ff:fe00:1122:8008~shs:mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=;net:fe80::aede:48ff:fe00:1122:8989~shs:mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=")
    assert Enum.count(matches) == 2
    Enum.each(matches, fn match ->
      assert {:ok, ip, port, _public_key} = match
      assert 'fe80::aede:48ff:fe00:1122' == :inet.ntoa(ip)
    end)
  end

  test "parse_annoucements with ws://" do
    matches = LD.parse_announcements("net:fe80::aede:48ff:fe00:1122:8008~shs:mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=;ws://[fe80::aede:48ff:fe00:1122]:8989~shs:mucTrTjExFklGdAFobgY4zypBAZMVi7q0m6Ya55gLVo=")
    assert Enum.count(matches) == 1
    Enum.each(matches, fn match ->
      assert {:ok, ip, port, _public_key} = match
      assert 'fe80::aede:48ff:fe00:1122' == :inet.ntoa(ip)
    end)

  end
end
