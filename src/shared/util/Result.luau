--!strict

export type Success<T> = {
	ok: true,
	value: T,
}

export type Failure<E> = {
	ok: false,
	error: E,
}

export type Result<T, E> = Success<T> | Failure<E>

local Result = {}

function Result.ok<T>(value: T): Success<T>
	return table.freeze({
		ok = true,
		value = value,
	})
end

function Result.err<E>(errorValue: E): Failure<E>
	return table.freeze({
		ok = false,
		error = errorValue,
	})
end

return table.freeze(Result)
