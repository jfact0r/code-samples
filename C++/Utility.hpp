namespace util
{
	template <class T>
	inline T clamp(T x, T min, T max)
	{
		return x < min ? min : (x > max ? max : x);
	}
}